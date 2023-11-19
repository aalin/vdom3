module VDOM
  class Server
    class App
      class TokenCookieNotSetError < StandardError
      end

      module RequestRefinements
        refine Async::HTTP::Protocol::HTTP2::Request do
          def deconstruct_keys(keys)
            keys.each_with_object({}) do |key, obj|
              var = "@#{key}"

              if instance_variable_defined?(var)
                obj[key] = instance_variable_get(var)
              end
            end
          end
        end
      end

      using RequestRefinements

      ALLOW_HEADERS = Ractor.make_shareable({
        "access-control-allow-methods" => "GET, POST, OPTIONS",
        "access-control-allow-headers" => [
          "content-type",
          "accept",
          "accept-encoding",
        ].join(", ")
      })

      ASSET_CACHE_CONTROL = [
        "public",
        "max-age=#{7 * 24 * 60 * 60}",
        "immutable",
      ].join(", ").freeze

      module States
        ACCEPTING = :accepting
        STOPPING = :stopping
      end

      def initialize(descriptor:, public_path:, root_path:, secret_key:)
        @state = States::ACCEPTING
        @descriptor = descriptor
        @public_path = public_path
        @sessions = SessionStore.new
        @file_cache = {}

        @environment = Environment.setup(
          root_path:,
          secret_key:
        )
      end

      def stopping? =
        @state == States::STOPPING

      def stop
        @state = States::STOPPING
        @sessions.stop!
      end

      def call(request, task: Async::Task.current)
        Console.logger.info(
          "#{request.method} #{request.path}",
        )

        case request
        in path: "/favicon.ico"
          handle_favicon(request)
        in path: %r{\A\/.mayu\/runtime\/.+\.js(\.map)?}
          handle_script(request)
        in path: "/.mayu", method: "OPTIONS"
          handle_options(request)
        in path: %r{\/.mayu\/session\/(?<session_id>[[:alnum:]]+)}, method: "GET"
          handle_session_resume(request, $~[:session_id])
        in path: %r{\/.mayu\/session\/(?<session_id>[[:alnum:]]+)}, method: "POST"
          handle_session_callback(request, $~[:session_id])
        in path: %r{\A/\.mayu/assets/(.+)\z}, method: "GET"
          handle_vdom_asset(request)
        in method: "GET"
          handle_session_start(request)
        else
          handle_404(request)
        end
      end

      def handle_favicon(_) =
        send_public_file("favicon.png", "image/png")

      def handle_script(request) =
        send_file(
          File.read(
            File.join(
              @environment.client_path,
              File.basename(request.path)
            )
          ),
          "application/javascript; charset=utf-8",
          origin_header(request)
        )

      def handle_404(request)
        Console.logger.error(self, "File not found at #{request.path.inspect}")

        Protocol::HTTP::Response[
          404,
          { "content-type" => "text/plain; charset-utf-8" },
          ["File not found at #{request.path}"]
        ]
      end

      def handle_vdom_asset(request)
        path = File.join("/", Pathname.new(request.path).relative_path_from('/.mayu/assets'))

        asset = Modules::System.get_asset(path)

        unless asset
          raise "COULD NOT FIND ASSET #{path.inspect}"
          return handle_404(request)
        end

        Protocol::HTTP::Response[
          200,
          {
            "content-type" => asset.content_type,
            "content-encoding" => asset.encoded_content.encoding,
            "cache-control" => ASSET_CACHE_CONTROL,
            **origin_header(request),
          },
          [asset.encoded_content.content.to_s]
        ]
      end

      def handle_options(request)
        headers = {
          **ALLOW_HEADERS,
          **origin_header(request),
        }

        Protocol::HTTP::Response[204, headers, []]
      end

      def handle_session_start(request)
        session = Session.new(
          environment: @environment,
          descriptor: @descriptor
        )

        @sessions.store(session)

        body = session.render

        Protocol::HTTP::Response[
          200,
          {
            "content-type" => "text/html; charset-utf-8",
            "set-cookie": set_token_cookie_value(session),
          },
          [body]
        ]
      end

      def handle_session_resume(request, session_id, task: Async::Task.current)
        session = @sessions.authenticate(session_id, get_token_cookie_value(request))

        return session_not_found_response unless session

        headers = {
          "content-type" => EventStream::CONTENT_TYPE,
          "content-encoding" => EventStream::CONTENT_ENCODING,
          "set-cookie": set_token_cookie_value(session),
          **origin_header(request),
        }

        body = EventStream::Writer.new

        body.write(
          Runtime::Patches::Initialize[session.dom_id_tree.serialize]
        )

        task.async do
          session_task = session.run

          begin
            while msg = session.take
              break if body.closed?
              body.write(msg)
            end
          ensure
            session_task.stop
            Console.logger.info("Stopped session")
          end
        end

        Protocol::HTTP::Response[200, headers, body]
      end

      def session_not_found_response(request)
        Protocol::HTTP::Response[
          404,
          {
            **origin_header(request),
            "content-type": "text/plain"
          },
          ["Session not found/invalid token"]
        ]
      end

      def handle_session_callback(request, session_id)
        session = @sessions.authenticate(session_id, get_token_cookie_value(request))

        return session_not_found_response unless session

        each_message(request) do |message|
          case message
          in "callback", String => callback_id, payload
            session.callback(callback_id, payload)
          in "pong", Numeric => time
            session.pong(time)
          end
        rescue => e
          Console.logger.error(self, e)
        end

        headers = {
          "set-cookie" => set_token_cookie_value(session),
          **origin_header(request),
        }

        Protocol::HTTP::Response[204, headers, []]
      end

      def each_message(request)
        buf = String.new

        request.body.each do |chunk|
          buf += chunk

          if idx = buf.index("\n")
            yield JSON.parse(buf[0..idx], symbolize_names: true)
            buf = buf[idx.succ..-1].to_s
          end
        end
      end

      def origin_header(request) =
        { "access-control-allow-origin" => request.headers["origin"] }

      def send_public_file(filename, content_type, headers = {})
        send_file(read_public_file(filename), content_type, headers)
      end

      def send_file(content, content_type, headers = {})
          Protocol::HTTP::Response[
          200,
          {
            "content-type" => content_type,
            "content-length" => content.bytesize,
            **headers
          },
          [content]
        ]
      end

      def read_public_file(filename)
        path =
          filename
            .then { File.expand_path(_1, "/") }
            .then { File.join(@public_path, _1) }
        # @file_cache[path] ||= File.read(path)
        File.read(path)
      end

      def get_token_cookie_value(request)
        Array(request.headers["cookie"]).each do |str|
          if match = str.match(/^mayu-token=(\w+)/)
            return match[1].to_s.tap { Session::Token.validate!(_1) }
          end
        end

        raise TokenCookieNotSetError
      end

      def set_token_cookie_value(session, ttl_seconds: 60)
        expires = Time.now.utc + ttl_seconds

        [
          "mayu-token=#{session.token}",
          "path=/.mayu/session/#{session.id}",
          "expires=#{expires.httpdate}",
          "secure",
          "HttpOnly",
          "SameSite=Strict"
        ].join("; ")
      end
    end
  end
end

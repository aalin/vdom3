# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "async"
require "async/io/trap"
require "async/barrier"
require "async/queue"
require "async/http/endpoint"
require "async/http/protocol/response"
require "async/http/server"
require_relative "environment"
require_relative "runtime"
require_relative "event_stream"
require_relative "message_cipher"

module VDOM
  class Server
    class Session
      class InvalidTokenError < StandardError
      end

      attr_reader :id
      attr_reader :token

      def initialize(environment:, descriptor:)
        @id = SecureRandom.alphanumeric(32)
        @token = SessionToken.generate

        @input = Async::Queue.new
        @output = Async::Queue.new
        @stop = Async::Condition.new

        @runtime = VDOM::Runtime.new(
          environment: environment,
          session_id: @id
        )
        @runtime.render(descriptor)
      end

      def render =
        @runtime.to_html
      def dom_id_tree =
        @runtime.dom_id_tree

      def stop =
        @stop.signal

      def run
        @runtime.run do
          barrier = Async::Barrier.new

          barrier.async do
            loop do
              @output.enqueue([@runtime.dequeue].flatten)
            end
          end

          barrier.async do
            @stop.wait
            dumped = MessageCipher.new(key: "foo").dump(@runtime)
            @output.enqueue(Patches::Transfer[dumped])
            barrier.stop
          end

          barrier.wait
        end
      end

      def take =
        @output.dequeue

      def callback(id, payload) =
        @runtime.callback(id, payload)

      def pong(time) =
        @input.enqueue([:pong, time])

      # def run(descriptor, task: Async::Task.current)
      #   VDOM::Runtime.run do |runtime|
      #     task.async { input_loop(runtime) }
      #     task.async { ping_loop }
      #     task.async { patch_loop(runtime) }
      #
      #     runtime.resume(VDOM::Descriptor[descriptor])
      #
      #     @stop.wait
      #   ensure
      #     runtime&.stop
      #   end
      # end

      private

      def input_loop(runtime, task: Async::Task.current)
        loop do
          msg = @input.dequeue
          task.async { handle_input(runtime, msg) }
        rescue Protocol::HTTP2::ProtocolError, EOFError => e
          Console.logger.error(self, e)
          raise
        rescue => e
          Console.logger.error(self, e)
        end
      end

      def handle_input(runtime, message)
        case message
        in :callback, callback_id, payload
          runtime.handle_callback(callback_id, payload)
        in :pong, time
          pong = current_ping_time - time
          puts format("Ping: %.2fms", pong)
        in unhandled
          puts "\e[31mUnhandled: #{unhandled.inspect}\e[0m"
        end
      rescue => e
        Console.logger.error(self, e)
      end

      def current_ping_time =
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

      def ping_loop
        loop do
          sleep 5
          @output.enqueue(VDOM::Patches::Ping[current_ping_time])
        end
      end

      def patch_loop(runtime)
        while patches = runtime.take
          @output.enqueue(patches)
          # Uncomment the following line to add some latency
          # sleep 0.0005
        end
      rescue IOError, Errno::EPIPE, Protocol::HTTP2::ProtocolError => e
        puts "\e[31m#{e.message}\e[0m"
      ensure
        @stop.signal
      end
    end

    module SessionToken
      TOKEN_LENGTH = 64

      def self.validate!(token) =
        unless valid_format?(token)
          raise InvalidTokenError
        end

      def self.valid_format?(token) =
        token.match?(/\A[[:alnum:]]{#{TOKEN_LENGTH}}\z/)

      def self.generate =
        SecureRandom.alphanumeric(TOKEN_LENGTH)

      def self.equal?(a, b) =
        if a.length == b.length
          OpenSSL.fixed_length_secure_compare(a, b)
        else
          false
        end
    end

    class SessionStore
      class SessionNotFound < StandardError
      end

      class InvalidToken < StandardError
      end

      TIMEOUT_SECONDS = 10

      def initialize
        @sessions = {}
      end

      def authenticate(id, token)
        session = @sessions.fetch(id) { raise SessionNotFound }
        SessionToken.equal?(session.token, token) && session
      end

      def store(session) =
        @sessions.store(session.id, session)

      def stop! =
        @sessions.each_value(&:stop)

      def clear_stale
        @sessions.delete_if do |session|
          if Async::Clock.now - session.last_update > TIMEOUT_SECONDS
            session.stop
            true
          end
        end
      end
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

    class App
      class TokenCookieNotSetError < StandardError
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

      def initialize(descriptor:, public_path:)
        @descriptor = descriptor
        @public_path = public_path
        @sessions = SessionStore.new
        @file_cache = {}

        @environment = Environment.setup(
          root_path: File.expand_path("../../", __dir__),
          client_path: File.join("client", "dist")
        )
      end

      def stop =
        @sessions.stop!

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
              @environment.root_path,
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
        asset =
          Assets.instance.fetch(File.basename(request.path)) do
            return handle_404(request)
          end

        Protocol::HTTP::Response[
          200,
          {
            "content-type" => asset.content.type,
            "content-encoding" => asset.content.encoding,
            "cache-control" => ASSET_CACHE_CONTROL,
            **origin_header(request),
          },
          [asset.content.to_s]
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
          Patches::Initialize[session.dom_id_tree.serialize]
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
            return match[1].to_s.tap { SessionToken.validate!(_1) }
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

    def initialize(bind:, localhost:, descriptor:, public_path:)
      @uri = URI.parse(bind)
      @app = App.new(descriptor:, public_path:)

      endpoint = Async::HTTP::Endpoint.new(@uri)

      if localhost
        endpoint = apply_local_certificate(endpoint)
      end

      @server = Async::HTTP::Server.new(
        @app,
        endpoint,
        scheme: @uri.scheme,
        protocol: Async::HTTP::Protocol::HTTP2,
      )
    end

    def run(task: Async::Task.current)
      interrupt = Async::IO::Trap.new(:INT)

      task.async do
        interrupt.install!
        puts "\e[3m Starting server on #{@uri} \e[0m"

        barrier = Async::Barrier.new

        listeners = @server.run

        interrupt.wait
        # interrupt.default!
        Console.logger.info("Got interrupt")
        @app.stop
        listeners.each(&:stop)
      ensure
        Console.logger.info("Stopped server")
      end
    end

    private

    def apply_local_certificate(endpoint)
      require "localhost"
      require "async/io/ssl_endpoint"

      authority = Localhost::Authority.fetch(endpoint.hostname)

      context = authority.server_context
      context.alpn_select_cb = ->(protocols) do
        protocols.include?("h2") ? "h2" : nil
      end

      context.alpn_protocols = ["h2"]
      context.session_id_context = "mayu"

      Async::IO::SSLEndpoint.new(endpoint, ssl_context: context)
    end
  end
end

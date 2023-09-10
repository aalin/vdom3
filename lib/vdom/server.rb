# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "async"
require "async/queue"
require "async/http/endpoint"
require "async/http/protocol/response"
require "async/http/server"
require_relative "runtime"

module VDOM
  class Server
    class Session
      attr_reader :id

      def initialize(descriptor:)
        @id = SecureRandom.alphanumeric(32)
        @input = Async::Queue.new
        @output = Async::Queue.new
        @stop = Async::Condition.new

        @runtime = VDOM::Runtime.new(session_id: @id)
        @runtime.render(descriptor)
      end

      def render =
        @runtime.to_html
      def dom_id_tree =
        @runtime.dom_id_tree

      def run
        @runtime.run do
          @runtime.mount

          barrier = Async::Barrier.new

          barrier.async do
            loop do
              patches = @runtime.dequeue

              serialized_patches = patches.map do
                VDOM::Patches.serialize(_1)
              end

              @output.enqueue(serialized_patches)
            end
          end

          barrier.async do
          end

          barrier.async do
            @stop.wait
            barrier.stop
          end

          barrier.wait
        end
      ensure
        @runtime.unmount
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
          @output.enqueue(
            VDOM::Patches.serialize([VDOM::Patches::Ping[current_ping_time]])
          )
        end
      end

      def patch_loop(runtime)
        while patches = runtime.take
          p patches
          @output.enqueue(patches.map { VDOM::Patches.serialize(_1) })
          # Uncomment the following line to add some latency
          # sleep 0.0005
        end
      rescue IOError, Errno::EPIPE, Protocol::HTTP2::ProtocolError => e
        puts "\e[31m#{e.message}\e[0m"
      ensure
        @stop.signal
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
      using RequestRefinements

      SESSION_ID_HEADER_NAME = "x-vdom-session-id"

      ALLOW_HEADERS = Ractor.make_shareable({
        "access-control-allow-methods" => "GET, POST, OPTIONS",
        "access-control-allow-headers" => [
          "content-type",
          "accept",
          "accept-encoding",
          SESSION_ID_HEADER_NAME,
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
        @sessions = {}
        @file_cache = {}
      end

      def call(request, task: Async::Task.current)
        Console.logger.info(
          "#{request.method} #{request.path}",
        )

        case request
        in path: "/favicon.ico"
          handle_favicon(request)
        in path: "/runtime.js" | "/session.js" | "/stream.js"
          handle_script(request)
        in path: "/.vdom", method: "OPTIONS"
          handle_options(request)
        in path: %r{\/.vdom\/session\/(?<session_id>[[:alnum:]]+)}, method: "GET"
          handle_session_resume(request, $~[:session_id])
        in path: %r{\/.vdom\/session\/(?<session_id>[[:alnum:]]+)}, method: "PATCH"
          handle_session_callback(request, $~[:session_id])
        in path: %r{\A/\.vdom/(.+)\z}, method: "GET"
          handle_vdom_asset(request)
        in method: "GET"
          handle_session_start(request)
        else
          handle_404(request)
        end
      end

      def handle_favicon(_) =
        send_file("favicon.png", "image/png")

      def handle_script(request) =
        send_file(
          File.basename(request.path),
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

      class DeflateWrapper
        def initialize(body)
          @body = body
          @deflate =
            Zlib::Deflate.new(
              Zlib::BEST_COMPRESSION,
              -Zlib::MAX_WBITS,
              Zlib::MAX_MEM_LEVEL,
              Zlib::HUFFMAN_ONLY
            )
        end

        def write(buf) =
          @body.write(@deflate.deflate(buf, Zlib::SYNC_FLUSH))

        def closed? =
          @body.closed

        def close
          @body.write(@deflate.flush(Zlib::FINISH))
          @deflate.close
          @body.close
        end
      end

      def handle_session_start(request)
        session = Session.new(descriptor: @descriptor)

        @sessions.store(session.id, session)

        body = session.render

        Protocol::HTTP::Response[
          200,
          { "content-type" => "text/html; charset-utf-8" },
          [body]
        ]
      end

      def handle_session_resume(request, session_id, task: Async::Task.current)
        session = @sessions.fetch(session_id) do
          return Protocol::HTTP::Response[404, {
            content_type: "text/plain"
          }, ["Session not found"]]
        end

        headers = {
          "content-type" => "x-mayu/json-stream",
          "access-control-expose-headers" => SESSION_ID_HEADER_NAME,
          **origin_header(request),
        }

        body = Async::HTTP::Body::Writable.new

        if request.headers["accept-encoding"] == "deflate-raw"
          headers["content-encoding"] = "deflate-raw"
          body = DeflateWrapper.new(body)
        end

        body.write(
          JSON.generate([
            Patches.serialize(Patches::Initialize[session.dom_id_tree.serialize])
          ]) + "\n"
        )

        headers[SESSION_ID_HEADER_NAME] = session.id

        task.async do |subtask|
          subtask.async do
            while msg = session.take
              body.write(JSON.generate(msg) + "\n")
            end
          end

          session.run
        ensure
          body&.close
        end

        Protocol::HTTP::Response[200, headers, body]
      end

      def handle_session_callback(request, session_id)
        session = @sessions.fetch(session_id) do
          Console.logger.error(self, "Could not find session #{session_id.inspect}")

          return Protocol::HTTP::Response[
            401,
            origin_header(request),
            ["Could not find session #{session_id.inspect}"]
          ]
        end

        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"
        puts "\e[31mSESSION: #{session.id}\e[0m"

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

        Protocol::HTTP::Response[204, origin_header(request), []]
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

      def send_file(filename, content_type, headers = {})
        content = read_public_file(filename)

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
      task.async do
        puts "\e[3m Starting server on #{@uri} \e[0m"

        @server.run.each(&:wait)
      ensure
        puts "\n\r\e[3;31m Stopped server \e[0m"
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
      context.session_id_context = "vdom"

      Async::IO::SSLEndpoint.new(endpoint, ssl_context: context)
    end
  end
end

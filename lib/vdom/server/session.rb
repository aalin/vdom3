require_relative "../runtime"

module VDOM
  class Server
    class Session
      module Token
        class InvalidTokenError < StandardError
        end

        TOKEN_LENGTH = 64

        def self.validate!(token)
          unless valid_format?(token)
            raise InvalidTokenError
          end
        end

        def self.valid_format?(token) =
          token.match?(/\A[[:alnum:]]{#{TOKEN_LENGTH}}\z/)

        def self.generate = SecureRandom.alphanumeric(TOKEN_LENGTH)

        def self.equal?(a, b) = RbNaCl::Util.verify64(a, b)
      end

      attr_reader :id
      attr_reader :token

      def initialize(environment:, descriptor:)
        @id = SecureRandom.alphanumeric(32)
        @token = Token.generate

        @input = Async::Queue.new
        @output = Async::Queue.new
        @stop = Async::Condition.new

        @engine = VDOM::Runtime::Engine.new(environment: environment, session_id: @id)
        @engine.render(descriptor)
      end

      def render
        puts "\e[3;33mRENDERING\e[0m"
        @engine.to_html
      end

      def dom_id_tree = @engine.dom_id_tree

      def stop = @stop.signal

      def run
        @engine.run do
          barrier = Async::Barrier.new

          barrier.async { loop { @output.enqueue([@engine.dequeue].flatten) } }

          barrier.async do
            @stop.wait
            dumped = @engine.environment.encrypted_marshal.dump(@engine)
            @output.enqueue(Runtime::Patches::Transfer[dumped])
            barrier.stop
          end

          barrier.wait
        end
      end

      def take = @output.dequeue

      def callback(id, payload) = @engine.callback(id, payload)

      def pong(time) = @input.enqueue([:pong, time])

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
        in [:callback, callback_id, payload]
          runtime.handle_callback(callback_id, payload)
        in [:pong, time]
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
          @output.enqueue(Runtime::Patches::Ping[current_ping_time])
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
  end
end

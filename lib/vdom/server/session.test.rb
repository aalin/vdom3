require "minitest/autorun"

require_relative "session"

class VDOM::Server::Session::Test < Minitest::Test
  def test_serialize
  end

  def with_runtime
    Sync do
      VDOM::Modules::System.run(__dir__) do
        yield(
          VDOM::Runtime.new(
            environment:
              VDOM::Environment.setup(File.join(__dir__, "..", "..")),
            session_id: VDOM::Server::Session::Token.generate
          )
        )
      end
    end
  end
end

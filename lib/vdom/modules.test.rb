require "minitest/autorun"

require_relative "dependency_graph"

class VDOM::Modules::System::Test < Minitest::Test
  def test_system
    VDOM::Modules::System.run("demo/") do |system|
      system.import("Demo.haml")

      VDOM::Modules::Watcher.run(system)
    end
  end
end

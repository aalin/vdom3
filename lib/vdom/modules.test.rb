require "bundler/setup"
require "minitest/autorun"
require "async"

require_relative "modules"

class VDOM::Modules::System::Test < Minitest::Test
  def test_system
    Sync do
      VDOM::Modules::System.run("demo/") do |system|
        system.import("pages/page.haml")
        task = VDOM::Modules::Watcher.run(system)
        # TODO: Update files or something, verify that they have updated
        sleep 1
        task.stop
      end
    end
  end
end

require "bundler/setup"
require "filewatcher"
require "pathname"

require_relative "component"
require_relative "modules/registry"
require_relative "modules/resolver"
require_relative "modules/dependency_graph"

module VDOM
  module Modules
    class System
      CURRENT_KEY = :CurrentModulesSystem

      def self.run(root, &) =
        use(new(root), &)

      def self.use(system)
        previous = Fiber[CURRENT_KEY]
        Fiber[CURRENT_KEY] = system
        yield system
      ensure
        Fiber[CURRENT_KEY] = previous
      end

      def self.current
        Fiber[CURRENT_KEY] or raise "No active system"
      end

      def self.import(path, source_file = "/") =
        current.import(path, source_file)

      attr_reader :root

      def initialize(root)
        @root = Pathname.new(File.expand_path(root, Dir.pwd))

        @resolver = Resolver.new(
          root: @root,
          extensions: ["", ".haml"]
        )

        @graph = DependencyGraph.new
      end

      def import(path, source_file = "/")
        resolved = @resolver.resolve(path, File.dirname(source_file))
        source = File.read(File.join(@root, resolved))

        component =
          Registry[resolved.to_s] ||= VDOM::Component::Loader.load_component(
            source,
            resolved
          )

        component::Export
      end

      def created(path)
      end

      def updated(path)
        return unless @graph.include?(path)
      end

      def deleted(path)
        Registry.delete(path)
      end

      def relative_from_root(absolute_path)
        Pathname.new(absolute_path).relative_path_from(@root)
      end

      def relative_to_absolute(relative_path)
        Pathname.new(File.join(@root), relative_path)
      end
    end

    class Watcher
      def self.run(system)
        Filewatcher.new([system.root]).watch do |changes|
          changes.each do |path, event|
            relative_from_root = system.relative_from_root(path)

            if event in :created | :deleted | :updated
              $stderr.puts "\e[33m#{event}: #{relative_from_root}\e[0m"
              system.send(event, relative_from_root)
            else
              $stderr.puts "\e[31mUnhandled event: #{event}: #{relative_from_root}\e[0m"
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $0
  VDOM::Modules::System.run("demo/") do |system|
    system.import("Demo.haml")

    VDOM::Modules::Watcher.run(system)
  end
end

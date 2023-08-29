require "bundler/setup"
require "filewatcher"
require "pathname"

require_relative "component"
require_relative "modules/registry"
require_relative "modules/resolver"
require_relative "modules/dependency_graph"
require_relative "modules/dot_exporter"

module VDOM
  module Modules
    class Mod < Module
      attr_reader :code
      attr_reader :path

      def initialize(code, path)
        @code = code
        @path = path
        System.register(path, self)
        instance_eval(@code, @path, 1)
      end

      def marshal_dump = [@code, @path]
      def marshal_load(data) = initialize(*data)
    end

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

      def self.register(path, mod) =
        current.register(path, mod)

      attr_reader :root

      def initialize(root)
        @root = Pathname.new(File.expand_path(root, Dir.pwd))

        @resolver = Resolver.new(
          root: @root,
          extensions: ["", ".haml"]
        )

        @graph = DependencyGraph.new
      end

      def register(path, mod)
        Registry[path] = mod
        @graph.add_node(path, mod)
      end

      def unregister(path)
        Registry.delete(path)
        @graph.delete_node(path)
      end

      def import(path, source_file = "/")
        resolved = @resolver.resolve(path, File.dirname(source_file))

        if found = @graph.get_obj(resolved)
          if @graph.include?(source_file.to_s)
            @graph.add_dependency(source_file.to_s, resolved)
          end

          return found
        end

        source = File.read(File.join(@root, resolved))

        mod =
          VDOM::Component::Loader.load_component(
            source,
            resolved
          )

        @graph.add_node(resolved, mod)

        if @graph.include?(source_file.to_s)
          @graph.add_dependency(source_file.to_s, resolved)
        end

        mod::Export
      end

      def created(path)
      end

      def updated(path)
        return unless @graph.include?(path)
      end

      def deleted(path)
        @graph.dfs2(path, :incoming) do |node|
          puts node
        end
      end

      def export_dot
        DotExporter.new(@graph).to_source
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

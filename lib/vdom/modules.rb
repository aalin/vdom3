# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "bundler/setup"
require "filewatcher"
require "pathname"

require_relative "component"
require_relative "modules/registry"
require_relative "modules/resolver"
require_relative "modules/dependency_graph"
require_relative "modules/dot_exporter"
require_relative "modules/watcher"
require_relative "modules/loaders"

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

      def reevaluate
        remove_const(:Export) if const_defined?(:Export)
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
          Loaders.load(
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
        parts = path.delete_prefix("/").split("/")

        if parts in ["pages", *path_parts, "page.haml" | "layout.haml"]
          import(path)
        end
      end

      def updated(path)
        return unless @graph.include?(path)

        dependants = @graph.dependants_of(path)

        Registry.delete(path)
        @graph.delete_node(path)

        dependants.each do
          @graph.get_obj(_1).reevaluate
        end
      end

      def deleted(path) =
        updated(path)

      def export_dot
        DotExporter.new(@graph).to_source
      end

      def relative_from_root(absolute_path)
        File.join("/", Pathname.new(absolute_path).relative_path_from(@root))
      end

      def relative_to_absolute(relative_path)
        File.join(@root, relative_path)
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

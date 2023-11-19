# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require_relative "assets"
require_relative "dependency_graph"
require_relative "dot_exporter"
require_relative "registry"
require_relative "resolver"

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

      def self.current =
        Fiber[CURRENT_KEY] or raise "No active system"

      def self.import(path, source_file = "/") =
        current.import(path, source_file)

      def self.register(path, mod) =
        current.register(path, mod)

      def self.add_asset(asset) =
        current.add_asset(asset)

      def self.get_asset(path) =
        current.get_asset(path)

      def self.get_assets_for_module(path) =
        current.get_assets_for_module(path)

      attr_reader :root

      def initialize(root)
        @root = Pathname.new(File.expand_path(root, Dir.pwd))

        @resolver = Resolver.new(
          root: @root,
          extensions: ["", ".haml"]
        )

        @assets = Assets.new

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

      def get_asset(path) =
        @assets.get(path)

      def get_assets_for_module(path) =
        @graph.get_obj(path).assets

      def import(path, source_file = "/")
        resolved_path = @resolver.resolve(path, File.dirname(source_file))

        mod = load_module(resolved_path)

        if @graph.include?(source_file.to_s)
          @graph.add_dependency(source_file.to_s, resolved_path)
        end

        mod && mod::Export
      end

      def load_module(resolved_path)
        if found = @graph.get_obj(resolved_path)
          return found
        end

        absolute_path = File.join(@root, resolved_path)

        mod =
          if File.exist?(absolute_path)
            Loaders.load(File.read(absolute_path), resolved_path)
          end

        @graph.add_node(resolved_path, mod)

        mod
      end

      def add_dependency(source, target) =
        @graph.add_dependency(source.to_s, target.to_s)

      def add_asset(asset) =
        @assets.add(asset)

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

      alias deleted updated

      def export_dot =
        DotExporter.new(@graph).to_source

      def relative_from_root(absolute_path) =
        File.join("/", Pathname.new(absolute_path).relative_path_from(@root))

      def relative_to_absolute(relative_path) =
        File.join(@root, relative_path)
    end
  end
end

# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "tsort"
require "set"
require "cgi"

module VDOM
  module Modules
    class DependencyGraph
      # This is basically a reimplementation of this library:
      # https://github.com/jriecken/dependency-graph

      class Direction
        Incoming = :incoming
        Outgoing = :outgoing
      end

      class Node
        attr_reader :obj
        attr_reader :incoming
        attr_reader :outgoing

        def initialize(obj)
          @obj = obj
          @incoming = Set.new
          @outgoing = Set.new
        end

        def delete(id)
          @incoming.delete(id)
          @outgoing.delete(id)
        end
      end

      def initialize
        @nodes = {}
      end

      def size =
        @nodes.size

      def include?(id) =
        @nodes.include?(id)

      def add_node(id, obj) =
        (@nodes[id] ||= Node.new(obj)).obj

      def delete_node(id)
        return unless @nodes.include?(id)
        @nodes.delete(id)
        delete_connections(id)
      end

      def delete_connections(id) =
        @nodes.each { |node| node.delete(id) }

      def get_node(id) =
        @nodes[id]

      def get_obj(id) =
        @nodes[id]&.obj

      def has_node?(id) =
        @nodes.include?(id)

      def add_dependency(source_id, target_id) =
        with_source_and_target(source_id, target_id) do |source, target|
          source.outgoing.add(target_id)
          target.incoming.add(source_id)
        end

      def remove_dependency(source_id, target_id) =
        with_source_and_target(source_id, target_id) do |source, target|
          source.outgoing.delete(target_id)
          source.incoming.delete(source_id)
        end

      def direct_dependencies_of(id) =
        @nodes.fetch(id).outgoing.to_a

      def direct_dependants_of(id) =
        @nodes.fetch(id).incoming.to_a

      def dependencies_of(id, started_at = nil, only_leaves: false, &block)
        raise "Circular" if id == started_at

        @nodes
          .fetch(id)
          .outgoing
          .map do |dependency|
            next nil unless yield dependency if block_given?

            dependencies = dependencies_of(dependency, started_at || id)

            if !only_leaves || dependencies.empty?
              dependencies.add(dependency)
            else
              dependencies
            end
          end
          .compact
          .reduce(Set.new, &:merge)
      end

      def dependants_of(id, started_at = nil, only_leaves: false)
        raise "Circular" if id == started_at

        @nodes
          .fetch(id)
          .incoming
          .map do |dependant|
            dependants = dependants_of(dependant, started_at || id)
            if !only_leaves || dependants.empty?
              dependants.add(dependant)
            else
              dependants
            end
          end
          .reduce(Set.new, &:merge)
      end

      def entry_nodes =
        @nodes.filter { _2.incoming.empty? }.keys

      def overall_order(only_leaves: true) =
        TSort.tsort(
          ->(&b) { @nodes.keys.each(&b) },
          ->(key, &b) { @nodes[key]&.outgoing&.each(&b) }
        )

      def paths =
        @nodes.keys

      def each_obj(&block) =
        @nodes.each_value { |node| yield node.obj }

      def dfs2(id, direction, visited: T::Set[String].new, &block)
        if visited.include?(id)
          return
        else
          visited.add(id)
        end

        @nodes
          .fetch(id)
          .send(direction)
          .each { dfs2(_1, direction, visited:, &block) }

        yield id
      end

      private

      def with_source_and_target(source_id, target_id, &block)
        yield(fetch_node(:source, source_id), fetch_node(:target, target_id))
      end

      def fetch_node(type, id)
        @nodes.fetch(id) do
          raise ArgumentError,
                "Could not find #{type} #{id.inspect} in #{@nodes.keys.inspect}"
        end
      end

      def dfs(node, direction, &block)
        node
          .send(direction)
          .each { |id| dfs(@nodes.fetch(id), direction, &block) }

        yield node
      end
    end
  end
end

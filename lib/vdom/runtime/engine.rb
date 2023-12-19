# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "async/barrier"
require "async/queue"

require_relative "vnodes"

module VDOM
  module Runtime
    class Engine
      class PatchSet
        include Enumerable

        def initialize = @patches = []
        def each(&) = @patches.each(&)
        def push(patch) = @patches.push(patch)
        alias << push
      end

      attr_reader :session_id
      attr_reader :environment

      def initialize(environment:, session_id:)
        @environment = environment
        @session_id = session_id
        @patches = Async::Queue.new
        @callbacks = {}
        @document = VNodes::VDocument.new(nil, parent: self)
        @running = false
      end

      def render(descriptor)
        @document.update(descriptor)
      end

      def root = self

      def to_html = @document.to_s

      def dom_id_tree = @document.dom_id_tree

      def clear_queue!
        puts "\e[33m#{@patches.dequeue.inspect}\e[0m" until @patches.empty?
      end

      def commit(patch_set)
        @patches.enqueue(patch_set.to_a) if @task
      end

      def run(&)
        raise "already running" if @task

        @task =
          Async do
            puts "mounting document"
            barrier = Async::Barrier.new

            barrier.async { @document.mount&.wait }

            barrier.async do
              puts "yielding"
              yield
            end

            barrier.wait
          ensure
            @document.unmount
            @task = nil
          end
      end

      def dequeue = @patches.dequeue

      def traverse(&) = @document.traverse(&)

      def add_listener(listener)
        puts "\e[32mRegistering listener #{listener.id}\e[0m"
        @callbacks.store(listener.id, listener)
      end

      def remove_listener(listener)
        puts "\e[33mRemoving listener #{listener.id}\e[0m"
        @callbacks.delete(listener.id)
      end

      def callback(id, payload)
        @callbacks.fetch(id).call(payload)
      end

      def patch
        if @patch_set
          yield @patch_set
          return
        end

        @patch_set = PatchSet.new

        begin
          yield @patch_set
        ensure
          patch_set = @patch_set
          @patch_set = nil
          commit(patch_set)
        end
      end

      def marshal_dump
        [@session_id, @document, @callbacks]
      end

      def marshal_load(a)
        @session_id, @document, @callbacks = a
        @task = Async::Task.current
        @patches = Async::Queue.new
      end
    end
  end
end

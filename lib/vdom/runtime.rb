# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "async"
require "async/barrier"
require "async/queue"
require "securerandom"
require "cgi"
require "pry"

require_relative "component"
require_relative "descriptors"
require_relative "patches"
require_relative "inline_style"

module VDOM
  INCLUDE_DEBUG_ID = true

  class Runtime
    module Components
      class Head < Component::Base
        def render
          @props => {
            session_id:,
            descriptor:
          }

          H[:__head,
            *descriptor.children,
            H[:script,
              type: "module",
              src: "/session.js##{session_id}",
              async: true,
            ],
            **descriptor.props
          ]
        end
      end
    end

    IdNode = Data.define(:id, :name, :children) do
      def self.[](id, name, children = nil)
        new(id, name, children)
      end

      def serialize
        if c = children
          { id:, name:, children: c.flatten.map(&:serialize) }
        else
          { id:, name:, }
        end
      end
    end

    class VNode
      def self.generate_id =
        SecureRandom.alphanumeric(10)

      attr_reader :id
      attr_reader :descriptor
      attr_reader :root
      attr_reader :parent

      def initialize(descriptor, parent: nil)
        @descriptor = descriptor
        @parent = parent
        @root = parent.root
        @id = VNode.generate_id
        puts "#{self.class.name} #{@id}"
      end

      def patch(&)
        if Fiber[:patch_set]
          yield Fiber[:patch_set]
          return
        end

        patch_set = PatchSet.new

        begin
          yield Fiber[:patch_set] = patch_set
        ensure
          @root.commit(patch_set)
          Fiber[:patch_set] = nil
        end
      end

      def traverse(&) =
        yield self

      def inspect =
        "#<#{self.class.name}##{@id} descriptor=#{@descriptor.inspect}>"

      def dom_ids =
        [@id]
      def dom_id_tree =
        IdNode[@id, dom_node_name]

      def mount =
        nil
      def unmount =
        nil

      def task =
        @parent.task

      def update_children_order =
        @parent.update_children_order

      def parent_element_id =
        @parent.parent_element_id

      def get_slotted(name) =
        @parent.get_slotted(name)

      def init_child_vnode(descriptor)
        case descriptor
        in Descriptors::Element[type: Class]
          VComponent.new(descriptor, parent: self)
        in Descriptors::Element[type: :slot]
          VSlot.new(descriptor, parent: self)
        in Descriptors::Element[type: :head]
          VComponent.new(
            Descriptors::H[
              Components::Head,
              descriptor:,
              session_id: @root.session_id
            ], parent: self)
        in Descriptors::Element[type: :__head]
          VElement.new(descriptor.with(type: :head), parent: self)
        in Descriptors::Element
          VElement.new(descriptor, parent: self)
        in Descriptors::Text
          VText.new(descriptor, parent: self)
        in String | Numeric
          VText.new(descriptor.to_s, parent: self)
        in Array
          VChildren.new(descriptor, parent: self)
        in Descriptors::Comment
          VComment.new(descriptor, parent: self)
        in NilClass
          nil
        else
          raise "Unhandled descriptor: #{descriptor.inspect}"
        end
      end
    end

    class VDocument < VNode
      def initialize(...)
        super
        @children = VChildren.new([@descriptor], parent: self)
      end

      def to_s
        "<!doctype html>\n#{@children.to_s}"
      end

      def dom_id_tree =
        @children.dom_id_tree.first.first

      def update(descriptor)
        patch do
          @children.update([descriptor])
        end
      end

      def mount
        @children.mount
      end

      def unmount
        @children.unmount
      end

      def update_children_order
        nil
      end
    end

    class VComponent < VNode
      def initialize(...)
        super(...)

        @instance = @descriptor.type.allocate
        @instance.instance_variable_set(:@props, @descriptor.props)
        @instance.send(:initialize, **@descriptor.props)
        @children = VChildren.new(@instance.render, parent: self)
      end

      def mount
        @children.mount

        @task = init_task
      end

      def unmount
        @children.unmount
        @task&.stop
        @instance.unmount
      end

      def traverse(&)
        yield self
        @children.traverse(&)
      end

      def dom_ids = @children.dom_ids
      def dom_id_tree = @children.dom_id_tree
      def to_s = @children.to_s

      def update(new_descriptor)
        old_props = @descriptor.props
        @descriptor = new_descriptor

        unless old_props == @descriptor.props
          @instance.instance_variable_set(:@props, @descriptor.props)
          @children.update(@instance.render)
        end
      end

      def get_slotted(name)
        Descriptors.group_by_slot(@descriptor.children)[name]
      end

      def marshal_dump
        [@id, @parent, @children, @descriptor, @instance]
      end

      def marshal_load(a)
        @id, @parent, @children, @descriptor, @instance = a
      end

      private

      def init_task
        Async do
          queue = Async::Queue.new

          @instance.define_singleton_method(:rerender!) do
            queue.enqueue(:update!)
          end

          @instance.mount

          loop do
            queue.wait
            @children.update(@instance.render)
          end
        end
      end
    end

    class VSlot < VNode
      def initialize(...)
        super
        @children = VChildren.new(get_slotted(@descriptor.props[:name]), parent: self)
      end

      def dom_id_tree = @children.dom_id_tree
      def dom_ids = @children.dom_ids

      def update(descriptor)
        @descriptor = descriptor
        @children.update(get_slotted(@descriptor.props[:name]))
      end

      def mount
        @children.mount
      end

      def unmount
        @children.unmount
      end

      def to_s
        @children.to_s
      end
    end

    class VChildren < VNode
      STRING_SEPARATOR = Descriptors::Comment[""]

      def initialize(...)
        super
        @children = []
        update(@descriptor)
      end

      def dom_ids = @children.map(&:dom_ids).flatten
      def dom_id_tree = @children.map(&:dom_id_tree)
      def to_s = @children.join

      def mount
        @children.each(&:mount)
      end

      def unmount
        @children.each(&:unmount)
      end

      def traverse(&)
        yield self
        @children.traverse(&)
      end

      def update(descriptors)
        patch do
          grouped = @children.group_by { Descriptors.get_hash(_1.descriptor) }

          new_children = normalize_descriptors(descriptors).map do |descriptor|
            if found = grouped[Descriptors.get_hash(descriptor)]&.shift
              found.update(descriptor)
              found
            else
              vnode = init_child_vnode(descriptor)
              vnode
            end
          end.compact

          @children = new_children

          @parent.update_children_order

          grouped.values.flatten.each(&:unmount)
        end
      end

      private

      def normalize_descriptors(descriptors)
        Array(descriptors)
          .flatten
          .map { Descriptors::Element.or_string(_1) }
          .compact
          .then { insert_comments_between_strings(_1) }
      end

      def insert_comments_between_strings(descriptors)
        [nil, *descriptors].each_cons(2).map do |prev, descriptor|
          case [prev, descriptor]
          in String, String
            [STRING_SEPARATOR, descriptor]
          else
            descriptor
          end
        end.flatten
      end
    end

    class VCallback < VNode
      attr_reader :callback_id

      def initialize(...)
        super
        @callback_id = SecureRandom.alphanumeric(32)
      end

      def update(descriptor)
        @descriptor = descriptor
      end
    end

    class VStyles < VNode
      def initialize(...)
        super
      end

      def unmount
        patch do |patches|
          patches << Patches::RemoveAttribute[]
        end
      end
    end

    class VElement < VNode
      VOID_ELEMENTS = %i[
        area base br col embed hr img input link meta param source track wbr
      ]

      Listener = Data.define(:id, :callback) do
        def self.[](callback) =
          new(SecureRandom.alphanumeric(32), callback)

        def call(payload)
          method = callback.component.method(callback.method_name)

          case method.parameters
          in []
            method.call
          in [[:req, Symbol]]
            method.call(payload)
          in [[:keyrest, Symbol]]
            method.call(**payload)
          end
        end

        def callback_js =
          "Mayu.callback(event,'#{id}')"
      end

      def initialize(...)
        super

        @attributes = {}

        patch do |patches|
          patches << Patches::CreateElement[@id, @descriptor.type]
          @attributes = update_attributes(@descriptor.props)
          @children = VChildren.new([], parent: self)
          @children.update(@descriptor.children)
        end
      end

      def dom_id_tree =
        IdNode[@id, dom_node_name, @children.dom_id_tree]
      def dom_node_name =
        @descriptor.type.to_s.upcase

      def mount =
        @children.mount

      def unmount
        patch do |patches|
          @children.unmount
          @attributes
              .values
              .select { _1.is_a?(Listener) }
              .each { @root.remove_listener(_1) }
          @attributes = {}
          patches << Patches::RemoveNode[@id]
        end
      end

      def update(new_descriptor)
        patch do |patches|
          @descriptor = new_descriptor
          @attributes = update_attributes(new_descriptor.props)
          @children.update(@descriptor.children)
        end
      end

      def traverse(&)
        yield self
        @children.traverse(&)
      end

      def to_s
        if INCLUDE_DEBUG_ID
          identifier = ' data-mayu-id="%s"' % @id
        end

        name = @descriptor.type.to_s.downcase.tr("_", "-")

        attributes = @attributes.map do |prop, value|
          next unless value

          if value == true
            next " #{prop}"
          end

          if prop == :style && value.is_a?(Hash)
            value = InlineStyle.stringify(value)
          end

          format(
            ' %s="%s"',
            CGI.escape_html(prop.to_s.tr("_", "-")),
            if value.is_a?(Listener)
              value.callback_js
            else
              CGI.escape_html(value.to_s)
            end
          )
        end.join

        if VOID_ELEMENTS.include?(@descriptor.type)
          "<#{name}#{identifier}#{attributes}>"
        else
          "<#{name}#{identifier}#{attributes}>#{@children.to_s}</#{name}>"
        end
      end

      def parent_dom_id = @id

      def update_children_order
        return unless @children

        dom_ids = @children.dom_ids

        return if @dom_ids == dom_ids

        patch do |patches|
          patches << Patches::ReplaceChildren[@id, @dom_ids = dom_ids]
        end
      end

      private

      def update_attributes(props)
        patch do |patches|
          return @attributes.keys.union(props.keys).map do |prop|
            old = @attributes[prop]
            new = props[prop] || nil

            if prop == :style
              update_style(patches, prop, old, new)
            elsif prop.start_with?("on")
              update_callback(patches, prop, old, new)
            else
              update_attribute(patches, prop, old, new)
            end
          end.compact.to_h
        end
      end

      def update_attribute(patches, prop, old, new)
        unless new
          patches << Patches::RemoveAttribute[@id, value]
          return
        end

        if old.to_s == new.to_s
          [prop, old]
        end

        patches << Patches::SetAttribute[@id, prop, new.to_s]
        [prop, new]
      end

      def update_style(patches, prop, old, new)
        unless new
          patches << Patches::RemoveAttribute[@id, :style]
          return
        end

        InlineStyle.diff(id, old || {}, new) do |patch|
          patches << patch
        end

        [prop, new]
      end

      def update_callback(patches, prop, old, new)
        if old
          if old.callback.same?(new)
            return [prop, old]
          end

          @root.remove_listener(old)

          unless new
            patches << Patches::RemoveAttribute[@id, prop]
            return
          end
        end

        return unless new

        listener = @root.add_listener(Listener[new])
        patches << Patches::SetAttribute[@id, prop, listener.callback_js]

        [prop, listener]
      end
    end

    class VText < VNode
      ZERO_WIDTH_SPACE = "&ZeroWidthSpace;"
      def initialize(...)
        super
        patch do |patches|
          patches << Patches::CreateTextNode[@id, @descriptor.to_s]
        end
      end

      def update(new_descriptor)
        unless @descriptor.to_s == new_descriptor.to_s
          @descriptor = new_descriptor
          patch do |patches|
            patches << Patches::SetTextContent[@id, @descriptor.to_s]
          end
        end
      end

      def unmount
        patch do |patches|
          patches << Patches::RemoveNode[@id]
        end
      end

      def to_s
        if @descriptor.to_s.empty?
          ZERO_WIDTH_SPACE
        else
          CGI.escape_html(@descriptor.to_s)
        end
      end

      def dom_node_name =
        "#text"
    end

    class VComment < VNode
      def initialize(...)
        super
        patch do |patches|
          patches << Patches::CreateComment[@id, escape_comment(@descriptor)]
        end
      end

      def update(descriptor)
        unless @descriptor.to_s == descriptor.to_s
          @descriptor = descriptor
          patch do |patches|
            patches << Patches::SetTextContent[@id, escape_comment(descriptor.to_s)]
          end
        end
      end

      def unmount
        patch do |patches|
          patches << Patches::RemoveNode[@id]
        end
      end

      def to_s =
        "<!--#{escape_comment(@descriptor.content)}-->"

      def dom_node_name =
        "#comment"

      private

      def escape_comment(str) =
        str.to_s.gsub(/--/, '&#45;&#45;')
    end

    class PatchSet
      include Enumerable

      def initialize
        @patches = []
      end

      def each(&) =
        @patches.each(&)

      def push(patch) =
        @patches.push(patch)

      alias << push
    end

    attr_reader :session_id

    def initialize(session_id:, task: Async::Task.current)
      @session_id = session_id
      @task = task
      @patches = Async::Queue.new
      @callbacks = {}
      @document = VDocument.new(nil, parent: self)
      @running = false
    end

    def render(descriptor)
      @document.update(descriptor)
    end

    def root =
      self

    def to_html =
      @document.to_s

    def dom_id_tree =
      @document.dom_id_tree

    def clear_queue! =
      until @patches.empty?
        puts "\e[33m#{@patches.dequeue.inspect}\e[0m"
      end

    def commit(patch_set)
      if @running
        @patches.enqueue(patch_set.to_a)
      end
    end

    def run(&)
      raise "already running" if @running

      begin
        @running = true
        yield
      ensure
        @running = false
      end
    end

    def mount =
      @document.mount

    def dequeue =
      @patches.dequeue

    def traverse(&) =
      @document.traverse(&)

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

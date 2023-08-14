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
  INCLUDE_DEBUG_ID = false

  class Runtime
    IdNode = Data.define(:id, :children) do
      def self.[](id, children = nil)
        new(id, children)
      end

      def serialize
        if c = children
          { id:, children: c.flatten.map(&:serialize) }
        else
          { id: }
        end
      end
    end

    class VNode
      def self.generate_id =
        SecureRandom.alphanumeric(10)

      attr_reader :descriptor
      attr_reader :root

      def initialize(descriptor, parent: nil)
        @descriptor = descriptor
        @parent = parent
        @root = parent.root
        @id = VNode.generate_id
      end

      def patch(&) =
        @root.patch(&)

      def traverse(&) =
        yield self

      def inspect =
        "#<#{self.class.name}##{@id} descriptor=#{@descriptor.inspect}>"

      def dom_ids =
        [@id]
      def dom_id_tree =
        IdNode[@id]

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
      end

      def to_s
        "<!doctype html>\n#{@child.to_s}"
      end

      def dom_id_tree
        @child&.dom_id_tree&.first
      end

      def update(descriptor)
        patch do
          @child = init_child_vnode(descriptor)
        end
      end

      def mount
        @child&.mount
      end

      def unmount
        @child&.unmount
      end

      def update_children_order
        nil
      end
    end

    class VComponent < VNode
      def initialize(...)
        super(...)

        @instance = @descriptor.type.new(**@descriptor.props)
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
        new_descriptor => Descriptors::Element[type: ^(@descriptor.type)]
        @descriptor = new_descriptor
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

      def dom_id_tree
        @children.dom_id_tree
      end

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

    class VElement < VNode
      VOID_ELEMENTS = %i[
        area base br col embed hr img input link meta param source track wbr
      ]

      def initialize(...)
        super

        patch do |patches|
          patches << Patches::CreateElement[@id, @descriptor.type]
          @children = VChildren.new([], parent: self)
          @children.update(@descriptor.children)
        end
      end

      def dom_id_tree
        IdNode[@id, @children.dom_id_tree]
      end

      def mount
        @children.mount
      end

      def unmount
        patch do |patches|
          @children.unmount
          patches << Patches::RemoveNode[@id]
        end
      end

      def update(new_descriptor)
        patch do
          update_attributes(@descriptor.props, new_descriptor.props)
          @descriptor = new_descriptor
          @children.update(@descriptor.children)
        end
      end

      def traverse(&)
        yield self
        @children.traverse(&)
      end

      def to_s
        attributes = @descriptor.props.map do |prop, value|
          if prop == :style && value.is_a?(Hash)
            value = InlineStyle.stringify(value)
          end

          format(
            ' %s="%s"',
            CGI.escape_html(prop.to_s.tr("_", "-")),
            CGI.escape_html(value)
          )
        end.join

        if INCLUDE_DEBUG_ID
          identifier = ' data-mayu-id="%s"' % @id
        end

        name = @descriptor.type.to_s.downcase.tr("_", "-")

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

      def update_attributes(old_props, new_props)
        patch do |patches|
          removed = new_props.keys.difference(old_props.keys)

          new_props.each do |attr, value|
            next if old_props[attr] == value

            if !value || value == ""
              removed.push(attr)
              next
            end

            if attr == :style && Hash == value
              InlineStyle.diff(@id, old_props[attr], value) do |patch|
                patches << patch
              end

              next
            end

            if value == true
              patches << Patches::SetAttribute[@id, attr.to_s, ""]
            else
              patches << Patches::SetAttribute[@id, attr.to_s, value.to_s]
            end
          end

          removed.each do |attr|
            patches << Patches::RemoveAttribute[@id, attr.to_s]
          end
        end
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

    def initialize(task: Async::Task.current)
      @task = task
      @document = VDocument.new(nil, parent: self)
      @patches = Async::Queue.new
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

    def mount =
      @document.mount

    def dequeue =
      @patches.dequeue

    def traverse(&) =
      @document.traverse(&)

    def patch(&)
      raise ArgumentError, "No block given" unless block_given?

      if @patch_set
        yield @patch_set
        return
      end

      begin
        @patch_set = PatchSet.new
        yield @patch_set
      ensure
        patch_set = @patch_set
        @patch_set = nil
        @patches.enqueue(patch_set.to_a)
      end
    end

    def marshal_dump
      [@document]
    end

    def marshal_load(a)
      @document = a.first
      @task = Async::Task.current
      @patches = Async::Queue.new
    end
  end
end

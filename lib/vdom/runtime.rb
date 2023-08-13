# frozen_string_literal: true

require "async"
require "async/barrier"
require "async/queue"
require "securerandom"
require "pry"

require_relative "patches"
require_relative "inline_style"

module VDOM
  INCLUDE_DEBUG_ID = true

  class Runtime
    IdNode = Data.define(:id, :children) do
      def self.[](id, children = nil)
        new(id, children)
      end

      def serialize
        if c = children
          {id:, children: c.flatten.map(&:serialize)}
        else
          {id:}
        end
      end
    end

    class VNode
      def self.generate_id =
        SecureRandom.alphanumeric(10)

      attr_reader :descriptor

      def initialize(descriptor, parent: nil)
        @descriptor = descriptor
        @parent = parent
        @id = VNode.generate_id
      end

      def traverse(&)
        yield self
      end

      def inspect
        "#<#{self.class.name}##{@id} descriptor=#{@descriptor.inspect}>"
      end

      def dom_ids = [@id]

      def dom_id_tree
        IdNode[@id]
      end

      def mount
      end

      def patch(descriptor)
      end

      def unmount
      end

      def task
        @parent.task
      end

      def update_children_order =
        @parent.update_children_order

      def parent_element_id =
        @parent.parent_element_id

      def get_slotted(name) =
        @parent.get_slotted(name)

      def init_vnode(descriptor)
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

      protected

      def emit_patch(patch)
        @parent.emit_patch(patch)
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
        @child = init_vnode(descriptor)
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

        @task = Async do
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
        grouped = @children.group_by { Descriptors.get_hash(_1.descriptor) }

        new_children = normalize_descriptors(descriptors).map do |descriptor|
          if found = grouped[Descriptors.get_hash(descriptor)]&.shift
            found.update(descriptor)
            found
          else
            vnode = init_vnode(descriptor)
            vnode
          end
        end.compact

        @children = new_children

        @parent.update_children_order

        grouped.values.flatten.each(&:unmount)
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
        emit_patch(Patches::CreateElement[@id, @descriptor.type])
        @children = VChildren.new([], parent: self)
        @children.update(@descriptor.children)
      end

      def dom_id_tree
        IdNode[@id, @children.dom_id_tree]
      end

      def mount
        @children.mount
      end

      def unmount
        @children.unmount
        emit_patch(Patches::RemoveNode[@id])
      end

      def update(new_descriptor)
        patch_attributes(@descriptor.props, new_descriptor.props)
        @descriptor = new_descriptor
        @children.update(@descriptor.children)
      end

      def traverse(&)
        yield self
        @children.traverse(&)
      end

      def to_s
        attributes = @descriptor.props.map do |prop, value|
          if prop == :style && value.is_a?(Hash)
            value = InlineStyle.new(value).to_s
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

        emit_patch(Patches::ReplaceChildren[@id, @dom_ids = dom_ids])
      end

      private

      def patch_attributes(old_props, new_props)
        removed = new_props.keys.difference(old_props.keys)

        new_props.each do |attr, value|
          next if old_props[attr] == value

          if !value || value == ""
            removed.push(attr)
            next
          end

          if attr == :style
            InlineStyle.new(old_props[attr]).diff(@id, value) do |patch|
              emit_patch(patch)
            end

            next
          end

          if value == true
            emit_patch(Patches::SetAttribute[@id, attr.to_s, ""])
          else
            emit_patch(Patches::SetAttribute[@id, attr.to_s, value.to_s])
          end
        end

        removed.each do |attr|
          emit_patch(Patches::RemoveAttribute[@id, attr.to_s])
        end
      end
    end

    class VText < VNode
      ZERO_WIDTH_SPACE = "&ZeroWidthSpace;"
      def initialize(...)
        super
        emit_patch(Patches::CreateTextNode[@id, @descriptor.to_s])
      end

      def update(new_descriptor)
        unless @descriptor.to_s == new_descriptor.to_s
          @descriptor = new_descriptor
          emit_patch(Patches::SetTextContent[@id, @descriptor.to_s])
        end
      end

      def unmount
        emit_patch(Patches::RemoveNode[@id])
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
        emit_patch(Patches::CreateComment[@id, escape_comment(@descriptor)])
      end

      def update(descriptor)
        unless @descriptor.to_s == descriptor.to_s
          @descriptor = descriptor
          emit_patch(Patches::SetTextContent[@id, escape_comment(descriptor.to_s)])
        end
      end

      def unmount
        emit_patch(Patches::RemoveNode[@id])
      end

      def to_s =
        "<!--#{escape_comment(@descriptor.content)}-->"

      def escape_comment(str) =
        str.to_s.gsub(/--/, '&#45;&#45;')
    end

    def initialize(task: Async::Task.current)
      @task = task
      @document = VDocument.new(nil, parent: self)
      @patches = Async::Queue.new
    end

    def render(descriptor)
      @document.update(descriptor)
    end

    def to_html =
      @document.to_s

    def dom_id_tree =
      @document.dom_id_tree

    def emit_patch(patch)
      @patches.enqueue(patch)
    end

    def clear_queue!
      until @patches.empty?
        puts "\e[33m#{@patches.dequeue.inspect}\e[0m"
      end
    end

    def mount
      @document.mount
    end

    def dequeue
      @patches.dequeue
    end

    def traverse(&)
      @document.traverse(&)
    end
  end
end

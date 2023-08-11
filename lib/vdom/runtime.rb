require "async"
require "async/barrier"
require "async/queue"
require "securerandom"
require "pry"

require_relative "patches"

module VDOM
  class Runtime
    class VNode
      def self.generate_id =
        SecureRandom.alphanumeric(10)

      attr_reader :descriptor

      def initialize(descriptor, parent: nil)
        @descriptor = descriptor
        @parent = parent
        @id = VNode.generate_id
      end

      def inspect
        "#<#{self.class.name}##{@id} descriptor=#{@descriptor.inspect}>"
      end

      def dom_id =
        @id

      def mount
      end

      def patch(descriptor)
      end

      def unmount
      end

      def task
        @parent.task
      end

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
        in Descriptors::Comment
          VComment.new(descriptor, parent: self)
        in Array
          VElement.new(Descriptors::H[:mayu_fragment, *descriptor], parent: self)
        in NilClass
          nil
        else
          raise "Unhandled descriptor: #{descriptor.inspect}"
        end
      end

      def update_children_order
        @parent.update_children_order
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

      def mount
        @child&.mount
      end

      def patch(descriptor)
        @child = init_vnode(descriptor)
        @child.mount
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

        @task = Async do
          queue = Async::Queue.new

          instance = @descriptor.type.new(**@descriptor.props)

          update_child(instance.render)

          instance.define_singleton_method(:rerender!) do
            queue.enqueue(:update!)
          end

          loop do
            queue.wait
            update_child(instance.render)
          end
        end
      end

      def dom_id =
        @child&.dom_id

      def to_s
        @child.to_s
      end

      def update(new_descriptor)
        new_descriptor => Descriptors::Element[type: ^(@descriptor.type)]
        @descriptor = new_descriptor
      end

      def get_slotted(name)
        Descriptors.group_by_slot(@descriptor.children)[name]
      end

      protected

      def update_child(new_child)
        if Descriptors.same?(@child&.descriptor, new_child)
          @child.update(new_child)
        else
          @child&.unmount
          @child = new_child ? init_vnode(new_child).tap(&:mount) : nil
          update_children_order
        end
      end
    end

    class VSlot < VNode
      def initialize(...)
        super
        @children = get_slotted(@descriptor.props[:name]).map { init_vnode(_1) }
      end

      def mount
      end

      def to_s
        @children.map(&:to_s).join
      end
    end

    class VElement < VNode
      VOID_ELEMENTS = %i[
        area base br col embed hr img input link meta param source track wbr
      ]

      def initialize(...)
        super(...)
        @children = []
      end

      def mount
        emit_patch(Patches::CreateElement[@id, @descriptor.type])
        update_children(Array(@descriptor.children).flatten)
      end

      def unmount
        emit_patch(Patches::RemoveNode[@id])
      end

      def update(descriptor)
        @descriptor = descriptor
        update_children(Array(@descriptor.children).flatten)
      end

      def to_s
        attributes = @descriptor.props.map do |prop, value|
          format(
            ' %s="%s"',
            CGI.escape_html(prop.to_s.tr("_", "-")),
            CGI.escape_html(value)
          )
        end.join

        identifier = ' data-mayu-id="%s"' % @id

        if VOID_ELEMENTS.include?(@descriptor.type)
          "<#{@descriptor.type}#{identifier}#{attributes}>"
        else
          "<#{@descriptor.type}#{identifier}#{attributes}>#{@children.join}</#{@descriptor.type}>"
        end
      end

      def update_children_order
        dom_ids = @children.map(&:dom_id)

        return if @dom_ids == dom_ids

        emit_patch(Patches::ReplaceChildren[@id, @dom_ids = dom_ids])
      end

      private

      def parent_element_id = @id

      def update_children(descriptors)
        grouped = @children.group_by { Descriptors.get_hash(_1.descriptor) }

        new_children = Array(descriptors).map.with_index do |descriptor|
          if found = grouped[Descriptors.get_hash(descriptor)]&.shift
            found.update(descriptor)
            found
          else
            vnode = init_vnode(descriptor)
            vnode.mount
            vnode
          end
        end.compact

        @children = new_children

        update_children_order

        grouped.values.flatten.each(&:unmount)
      end
    end

    class VText < VNode
      def mount
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
          "&ZeroWidthSpace;"
        else
          CGI.escape_html(@descriptor.to_s)
        end
      end
    end

    class VComment < VNode
      def to_s =
        "<!-- #{CGI.escape_html(@descriptor.content)} -->"
    end

    def initialize(task: Async::Task.current)
      @task = task
      @document = VDocument.new(nil, parent: self)
    end

    def render(descriptor)
      @document.patch(descriptor)
    end

    def to_html =
      @document.to_s

    def emit_patch(patch)
      puts "\e[34m#{patch}\e[0m"
    end
  end
end

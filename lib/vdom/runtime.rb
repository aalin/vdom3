require "securerandom"
require "pry"

module VDOM
  class Runtime
    class VNode
      def self.generate_id =
        SecureRandom.alphanumeric(10)

      def initialize(descriptor, parent: nil)
        @descriptor = descriptor
        @id = VNode.generate_id
      end

      private

      def init_vnode(descriptor)
        case descriptor
        in Descriptors::Element[type: Class]
          VComponent.new(descriptor, parent: self)
        in Descriptors::Element[type: Symbol]
          VElement.new(descriptor, parent: self)
        in Descriptors::Text | String
          VText.new(descriptor, parent: self)
        in Descriptors::Comment
          VComment.new(descriptor, parent: self)
        in Array
          VFragment.new(descriptor, parent: self)
        in NilClass
          nil
        else
          p descriptor
          raise
        end
      end
    end

    class VFragment < VNode
      def initialize(...)
        super
        @children = @descriptor.map { init_vnode(_1) }
      end

      def to_s
        "<mayu-fragment>#{@children.map(&:to_s).join}</mayu-fragment>"
      end
    end

    class VDocument < VNode
      def to_s
        "<!doctype html>\n#{@child.to_s}"
      end

      def patch(descriptor)
        @child = init_vnode(descriptor)
      end
    end

    class VComponent < VNode
      def initialize(...)
        super(...)
        @instance = @descriptor.type.new(**@descriptor.props)
        @children = Array(@instance.render).map { init_vnode(_1) }
      end

      def to_s
        Array(@children).compact.map(&:to_s).join
      end

      def update(new_descriptor)
        new_descriptor => Descriptors::Element[type: ^(@descriptor.type)]
        @descriptor = new_descriptor
      end
    end

    class VElement < VNode
      VOID_ELEMENTS = %i[
        area base br col embed hr img input link meta param source track wbr
      ]

      def initialize(...)
        super(...)
        @children = Array(@descriptor.children).flatten.map { init_vnode(_1) }
      end

      def to_s
        attributes = @descriptor.props.map do |prop, value|
          format(
            ' %s="%s"',
            CGI.escape_html(prop.to_s.tr("_", "-")),
            CGI.escape_html(value)
          )
        end.join

        if VOID_ELEMENTS.include?(@descriptor.type)
          "<#{@descriptor.type}#{attributes}>"
        else
          "<#{@descriptor.type}#{attributes}>#{@children.join}</#{@descriptor.type}>"
        end
      end
    end

    class VText < VNode
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

    def initialize
      @document = VDocument.new(nil, parent: self)
    end

    def render(descriptor)
      @document.patch(descriptor)
    end

    def to_html =
      @document.to_s
  end
end

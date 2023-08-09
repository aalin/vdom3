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
        in Descriptors::Element[type: Component]
          VComponent.new(self, descriptor)
        in Descriptors::Element[type: Symbol]
          VElement.new(self, descriptor)
        in Descriptors::Text
          VText.new(self, descriptor)
        in Descriptors::Comment
          VComment.new(self, descriptor)
        end
      end
    end

    class VDocument < VNode
      def to_s
        "<!doctype html>\n#{@child}"
      end

      def patch(descriptor)
      end
    end

    class VComponent < VNode
      def initialize(...)
        super
      end

      def to_s =
        @children.map(&:to_s)

      def update(new_descriptor)
        new_descriptor => Descriptors::Element[type: @descriptor.type]
        @descriptor = new_descriptor
      end
    end

    class VElement < VNode
      VOID_ELEMENTS = %i[
        area base br col embed hr img input link meta param source track wbr
      ]

      def to_s
        attributes = @descriptor.props.map do |prop, value|
          format(
            ' %s="%s"',
            CGI.escape_html(prop.to_s.tr("_", "-")),
            CGI.escape_html(value)
          )
        end

        if VOID_ELEMENTS.include?(@descriptor.type)
          "<#{@descriptor.type}#{attributes}>"
        else
          "<#{@descriptor.type}#{attributes}>#{children}</#{@descriptor.type}>"
        end
      end
    end

    class VText < VNode
      def to_s
        if @descriptor.content.empty?
          "&ZeroWidthSpace;"
        else
          CGI.escape_html(@descriptor.content)
        end
      end
    end

    class VComment < VNode
      def to_s =
        "<!-- #{CGI.escape_html(@descriptor.content)} -->"
    end

    def initialize
      @root = VDocument.new(parent: self)
    end

    def render(descriptor)
      @root.patch(descriptor)
    end
  end
end

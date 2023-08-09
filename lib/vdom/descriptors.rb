module VDOM
  module Descriptors
    Element = Data.define(:type, :key, :slot, :children, :props) do
      def same?(other)
        if self.class === other && type == other.type && key == other.key
          if type == :input
            props[:type] == other.props[:type]
          else
            true
          end
        else
          false
        end
      end
    end

    Text = Data.define(:content) do
      def to_s = content
      def same?(other) = self.class === other
    end

    Comment = Data.define(:content) do
      def same?(other) =
        self.class === other
    end

    StyleSheet = Data.define(:content)

    module H
      extend self

      def element(type, *children, key: nil, slot: nil, **props) =
        Element[type, key, slot, children, props]
      alias [] element

      def custom_element(name, template, stylesheet) =
        CustomElement[name, template, stylesheet]

      def text(content) =
        Text[content]

      def comment(content) =
        Comment[content]

      def merge_props(*props)
        props.reduce({}) { |acc, props| acc.merge(props) }
      end
    end
  end
end

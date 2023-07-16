module VDOM
  module Descriptors
    Element = Data.define(:type, :key, :slot, :children, :props)
    CustomElement = Data.define(:name, :template, :tags, :stylesheet)
    Text = Data.define(:content)
    Comment = Data.define(:content)
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

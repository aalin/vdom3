module VDOM
  module Descriptors
    Element = Data.define(:type, :key, :slot, :children, :props)
    CustomElement = Data.define(:name, :template, :stylesheet)
    Text = Data.define(:content)
    Comment = Data.define(:content)
    StyleSheet = Data.define(:content)

    module H
      def element(type, *children, key: nil, slot: nil, **props) =
        Element[type, key, slot, children, props]
      alias [] element
      def custom_element(name, template) =
        CustomElement[name, template, stylesheet]
      def text(content) =
        Text[content]
      def comment(content) =
        Comment[content]
    end
  end
end

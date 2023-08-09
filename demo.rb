require_relative "lib/vdom"
require_relative "lib/vdom/component"

class HTMLRenderer
  VOID_ELEMENTS = %w[
    area base br col embed hr img input link meta param source track wbr
  ]

  def render(descriptor)
    case descriptor
    in Array
      render_fragment(descriptor)
    in VDOM::Descriptors::Text
      descriptor.content
    in VDOM::Descriptors::Comment
      render_comment(element)
    in VDOM::Descriptors::Element
      render_element(descriptor)
    in VDOM::Descriptors::CustomElement
      render_custom_element(descriptor)
    in NilClass | FalseClass
      ""
    in String | Symbol | Numeric | TrueClass
      descriptor.to_s
    end
  end

  private

  def render_fragment(array)
    contents = array.map { render(_1) }.join
    "<mayu-fragment>#{contents}</mayu-fragment>"
  end

  def render_text(text) =
    text.content.to_s

  def render_comment(comment) =
    "<!-- #{comment.content} -->"

  def render_element(element)
    case element.type
    in Symbol
      if VOID_ELEMENTS.include?(element.type)
        "<#{element.type}>"
      else
        children = element.children.map { render(_1) }.join
        "<#{element.type}>#{children}</#{element.type}>"
      end
    in VDOM::Descriptors::CustomElement => custom_element
      template = "<template>#{render(custom_element.tags)}</template>"
      slots = render(element.props.fetch(:slots, []))
      "<#{custom_element.name} shadowrootmode=\"open\">#{template}#{slots}</#{custom_element.name}>"
    end
  end

  def render_custom_element(custom_element)
    "<#{custom_element.name}></#{custom_element.name}>"
  end
end

require "syntax_tree/xml"

renderer = HTMLRenderer.new

Component = VDOM::Component::Loader.load_file("demo.haml")

component = Component.new

output = renderer.render(component.render)

puts SyntaxTree::XML.format(output)

require_relative "lib/vdom"
require_relative "lib/vdom/component"
require_relative "lib/vdom/runtime"

require "syntax_tree/xml"

runtime = VDOM::Runtime.new

Component = VDOM::Component::Loader.load_file("demo.haml")

runtime.render(VDOM::Descriptors::H[Component])

html = runtime.to_html
p html
puts SyntaxTree::XML.format(html.sub(/\A<!doctype html>\n/, ''))

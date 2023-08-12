require_relative "lib/vdom"
require_relative "lib/vdom/component"
require_relative "lib/vdom/runtime"

require "syntax_tree/xml"

Sync do |task|
  runtime = VDOM::Runtime.new

  Layout = VDOM::Component::Loader.load_file("demo/layout.haml")
  Component = VDOM::Component::Loader.load_file("demo/Demo.haml")

  H = VDOM::Descriptors::H

  puts "before render"

  task.async do
    runtime.render(H[Layout, H[Component]])
  end

  sleep 0.5

  runtime.traverse do |node|
    p node.class.name
  end

  html = runtime.to_html
  puts SyntaxTree::XML.format(html.sub(/\A<!doctype html>\n/, ''))
  puts runtime.dom_id_tree.inspect
end

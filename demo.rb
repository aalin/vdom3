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
  formatted_html = SyntaxTree::XML.format(html.sub(/\A<!doctype html>\n/, ''))
  puts formatted_html
  id_tree = runtime.dom_id_tree
  p id_tree
  runtime.clear_queue!

  File.write("output.html", html.sub("</html>", '<script type="module">import "./events.js"</script>\0'))
  File.write("output-formatted.html", formatted_html)

  task.async do
    runtime.mount

    File.open("events.js", "w") do |f|
      f.puts "import Runtime from './runtime.js'"

      f.puts "const runtime = new Runtime(#{JSON.generate(id_tree.serialize)})"

      f.puts "function sleep(milliseconds) { return new Promise((resolve) => setTimeout(resolve, milliseconds)) }"

      last_update = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

      50.times do |i|
        patch = runtime.dequeue
        puts "\e[32m#{i} \e[34m#{patch.inspect}\e[0m"

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
        diff = now - last_update
        last_update = now

        f.puts "await sleep(#{diff})"
        f.puts "runtime.#{patch.class.name.split('::').last}(#{patch.deconstruct.map {JSON.generate(_1)}.join(", ")})"
        # f.puts "runtime.apply(#{JSON.generate(VDOM::Patches.serialize(patch))})"
      end
    end
  rescue => e
    p e
  end
end

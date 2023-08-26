require "bundler/setup"

require_relative "lib/vdom"
require_relative "lib/vdom/component"
require_relative "lib/vdom/runtime"
require_relative "lib/vdom/modules"

require "syntax_tree/xml"

Sync do |task|
  runtime = VDOM::Runtime.new

  VDOM::Modules::System.run("demo/") do
    layout = VDOM::Modules::System.import("layout.haml")
    component = VDOM::Modules::System.import("Demo.haml")

    H = VDOM::Descriptors::H
    System = VDOM::Descriptors::H

    puts "before render"

    task.async do
      runtime.render(H[layout, H[component]])
    end

    sleep 0.5

    runtime.traverse do |node|
      p node.class.name
    end

    html = runtime.to_html
    puts html
    formatted_html = SyntaxTree::XML.format(html.sub(/\A<!doctype html>\n/, ''))
    puts formatted_html
    id_tree = runtime.dom_id_tree
    p(id_tree:)
    runtime.clear_queue!

    File.write("dump.marshal", Marshal.dump(runtime))
    runtime = Marshal.load(File.read("dump.marshal"))

    File.write("output.html", html.sub("</html>", '<script type="module">import "./events.js"</script>\0'))
    File.write("output-formatted.html", formatted_html)

    task.async do
      runtime.mount

      File.open("events.js", "w") do |f|
        f.puts "import Runtime from './runtime.js'"

        f.puts "const runtime = new Runtime(#{JSON.generate(id_tree.serialize)})"

        f.puts "function sleep(milliseconds) { return new Promise((resolve) => setTimeout(resolve, milliseconds)) }"

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
        last_update = start

        0.upto(Float::INFINITY) do |i|
          patches = runtime.dequeue
          patches.each do
            puts "\e[32m#{i} \e[34m#{_1.inspect}\e[0m"
          end

          now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          diff = now - last_update
          last_update = now

          f.puts "await sleep(#{diff})"
          serialized_patches = patches.map { VDOM::Patches.serialize(_1) }
          f.puts "runtime.apply(#{JSON.generate(serialized_patches)})"

          break if now - start > 15_000
        end
      end
    rescue => e
      p e
    end
  end
end

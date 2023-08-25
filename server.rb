require_relative "lib/vdom"
require_relative "lib/vdom/component"
require_relative "lib/vdom/runtime"
require_relative "lib/vdom/server"

Layout = VDOM::Component::Loader.load_file("demo/layout.haml")
Component = VDOM::Component::Loader.load_file("demo/Demo.haml")

H = VDOM::Descriptors::H

Sync do
  server = VDOM::Server.new(
    bind: "https://localhost:8080",
    localhost: true,
    component: H[Layout, H[Component]],
    public_path: __dir__
  )

  server.run
end

require "bundler/setup"
require_relative "lib/vdom"
require_relative "lib/vdom/descriptors"
require_relative "lib/vdom/runtime"
require_relative "lib/vdom/server"

H = VDOM::Descriptors::H

Sync do
  VDOM::Modules::System.run("demo/") do |system|
    layout = VDOM::Modules::System.import("pages/layout.haml")
    page = VDOM::Modules::System.import("pages/page.haml")

    server = VDOM::Server.new(
      bind: "https://localhost:8080",
      localhost: true,
      descriptor: H[layout, H[page]],
      public_path: File.join(__dir__, "public"),
      root_path: __dir__
    )

    server.run
  end
end

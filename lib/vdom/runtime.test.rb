require "minitest/autorun"

require "nokogiri"

require_relative "runtime"
require_relative "environment"
require_relative "modules"
require_relative "server"

class VDOM::Runtime::Test < Minitest::Test
  H = VDOM::Descriptors::H

  class Layout < VDOM::Component::Base
    COMPONENT_META = VDOM::Component::Metadata["Layout", __FILE__]

    def render
      H[:html, H[:body, H[:slot]]]
    end
  end

  class ComponentWithSlots < VDOM::Component::Base
    COMPONENT_META = VDOM::Component::Metadata["ComponentWithSlots", __FILE__]

    def render
      H[:body, H[:heading, H[:slot, name: "heading"]]]
    end
  end

  def test_render
    with_runtime do |runtime|
      runtime.render(H[:body, H[:h1, "Title"]])

      assert_equal get_body_html(runtime.to_html), <<~HTML.chomp
        <body><h1>Title</h1></body>
      HTML
    end
  end

  def test_attributes
    with_runtime do |runtime|
      runtime.render(
        H[
          Layout,
          H[:a, "Go to other page", href: "/other-page", class: "my-class"]
        ]
      )

      assert_equal get_body_html(runtime.to_html), <<~HTML.chomp
        <body><a href="/other-page" class="my-class">Go to other page</a></body>
      HTML

      runtime.render(
        H[
          Layout,
          H[:a, "Go to other page", href: "/other-page2", class: "my-class"]
        ]
      )

      read_patches(runtime) { p _1 }

      assert_equal get_body_html(runtime.to_html), <<~HTML.chomp
        <body><a href="/other-page2" class="my-class">Go to other page</a></body>
      HTML
    end
  end

  def test_slots
    with_runtime do |runtime|
      runtime.render(
        H[
          ComponentWithSlots,
          H[:h1, "Title", slot: "heading"],
          H[:h1, "Unused", slot: "unused-slot"]
        ]
      )

      assert_equal get_body_html(runtime.to_html), <<~HTML.chomp
        <body><heading><h1>Title</h1></heading></body>
      HTML

      runtime.render(
        H[ComponentWithSlots, H[:h1, "Updated title", slot: "heading"]]
      )

      assert_equal get_body_html(runtime.to_html), <<~HTML.chomp
        <body><heading><h1>Updated title</h1></heading></body>
      HTML
    end
  end

  def test_head
    with_runtime do |runtime|
      runtime.render(
        H[
          :div,
          H[:head,
            H[:title, "hello"]
          ],
          H[:article, "foobar"]
        ]
      )

      assert_equal Nokogiri.HTML(runtime.to_html).at("title").to_s,
        "hello"
    end
  end

  def read_patches(runtime)
    patches = runtime.instance_variable_get(:@patches)
    yield patches.dequeue until patches.empty?
  end

  def with_runtime
    Sync do
      VDOM::Modules::System.run(__dir__) do
        yield(
          VDOM::Runtime.new(
            environment:
              VDOM::Environment.setup(
                root_path: File.join(__dir__, "..", ".."),
                secret_key: "secret key",
              ),
            session_id: VDOM::Server::Session::Token.generate
          )
        )
      end
    end
  end

  def get_body_html(html)
    Nokogiri.HTML(html).at("body").to_s
  end
end

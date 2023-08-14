require "minitest/autorun"

require_relative "runtime"

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
      H[:div,
        H[:heading,
          H[:slot, name: "heading"],
        ]
      ]
    end
  end

  def test_render
    Sync do
      runtime = VDOM::Runtime.new

      runtime.render(
        H[:div,
          H[:h1, "Title"]
        ]
      )

      assert_equal runtime.to_html, <<~HTML.chomp
        <!doctype html>
        <div><h1>Title</h1></div>
      HTML
    end
  end

  def test_attributes
    Sync do
      runtime = VDOM::Runtime.new

      runtime.render(
        H[Layout,
          H[:a, "Go to other page", href: "/other-page", class: "my-class"],
        ]
      )

      assert_equal runtime.to_html, <<~HTML.chomp
        <!doctype html>
        <html><body><a href="/other-page" class="my-class">Go to other page</a></body></html>
      HTML

      runtime.render(
        H[Layout,
          H[:a, "Go to other page", href: "/other-page2", class: "my-class"],
        ]
      )

      read_patches(runtime) do
        p _1
      end

      assert_equal runtime.to_html, <<~HTML.chomp
        <!doctype html>
        <html><body><a href="/other-page2" class="my-class">Go to other page</a></body></html>
      HTML
    end
  end

  def test_slots
    Sync do
      runtime = VDOM::Runtime.new

      runtime.render(
        H[ComponentWithSlots,
          H[:h1, "Title", slot: "heading"],
          H[:h1, "Unused", slot: "unused-slot"],
        ]
      )

      assert_equal runtime.to_html, <<~HTML.chomp
        <!doctype html>
        <div><heading><h1>Title</h1></heading></div>
      HTML

      runtime.render(
        H[ComponentWithSlots,
          H[:h1, "Updated title", slot: "heading"],
        ]
      )

      assert_equal runtime.to_html, <<~HTML.chomp
        <!doctype html>
        <div><heading><h1>Updated title</h1></heading></div>
      HTML
    end
  end

  def read_patches(runtime)
    patches = runtime.instance_variable_get(:@patches)
    yield patches.dequeue until patches.empty?
  end
end

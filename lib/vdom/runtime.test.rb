require "minitest/autorun"

require_relative "runtime"

class VDOM::Runtime::Test < Minitest::Test
  H = VDOM::Descriptors::H

  class ComponentWithSlots < VDOM::Component::Base
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
end

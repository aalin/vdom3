require "minitest/autorun"

require_relative "descriptors"

class VDOM::Descriptors::Element::Test < Minitest::Test
end

class VDOM::Descriptors::H::Test < Minitest::Test
  H = VDOM::Descriptors::H

  def test_build_elements
    element = H[:div, my_prop: "foo", key: "bar", lol: 123]
    assert_instance_of VDOM::Descriptors::Element, element
    assert_equal element.type, :div
    assert_equal element.props, { my_prop: "foo", lol: 123 }
    assert_equal element.key, "bar"
    assert_equal element.children, []
  end
end

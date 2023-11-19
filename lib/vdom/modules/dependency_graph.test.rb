require "minitest/autorun"

require_relative "dependency_graph"

class VDOM::Modules::DependencyGraph::Test < Minitest::Test
  def test_basic
    graph = VDOM::Modules::DependencyGraph.new

    graph.add_node("a", 1)
    graph.add_node("b", 2)
    graph.add_node("c", 3)

    assert_equal(3, graph.size)

    graph.add_dependency("a", "b")
    graph.add_dependency("b", "c")

    assert_equal %w[], graph.dependants_of("a").to_a
    assert_equal %w[c b], graph.dependencies_of("a").to_a

    assert_equal %w[a], graph.dependants_of("b").to_a
    assert_equal %w[c], graph.dependencies_of("b").to_a

    assert_equal %w[a b], graph.dependants_of("c").to_a
    assert_equal %w[], graph.dependencies_of("c").to_a

    assert_equal %w[c b a], graph.overall_order

    assert_equal %w[c b a], graph.overall_order(only_leaves: true)
  end

  Component = Data.define(:path, :imports)

  def test_complex
    graph =
      build_graph(
        {
          "page" => %w[Header Section Carousel],
          "page2" => %w[Header Section Details Figure Counter],
          "Figure" => %w[Image],
          "Carousel" => %w[Image next.svg prev.svg],
          "Counter" => %w[Card Button]
        }
      )

    assert_equal %w[page2 Counter], graph.dependants_of("Card").to_a

    assert_equal %w[page2 Figure page Carousel],
                 graph.dependants_of("Image").to_a

    assert_equal %w[page2], graph.dependants_of("Details").to_a

    assert_equal %w[], graph.dependants_of("page2").to_a

    assert_equal %w[Header Section Details Image Figure Card Button Counter],
                 graph.dependencies_of("page2").to_a

    assert_equal %w[page page2], graph.entry_nodes

    assert_equal %w[
                   Header
                   Section
                   Image
                   next.svg
                   prev.svg
                   Carousel
                   page
                   Details
                   Figure
                   Card
                   Button
                   Counter
                   page2
                 ],
                 graph.overall_order
  end

  def build_graph(dependencies)
    graph = VDOM::Modules::DependencyGraph.new

    dependencies.each do |path, deps|
      graph.add_node(path, nil) unless graph.include?(path)

      deps.each do |dep|
        graph.add_node(dep, nil) unless graph.include?(dep)
        graph.add_dependency(path, dep)
      end
    end

    graph
  end
end

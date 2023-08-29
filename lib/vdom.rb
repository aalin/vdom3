require_relative "vdom/descriptors"

module VDOM
  H = Descriptors::H

  def self.merge_props(component, *sources)
    result = sources.reduce({}, &:merge)

    if result.delete(:class)
      classes = sources.map { _1[:class] }.flatten.compact
      p classes
      # result[:class] = component.styles[*classes]
    end

    result
  end
end

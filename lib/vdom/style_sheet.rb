module VDOM
  NullStyleSheet = Data.define(:component_class) do
    def [](*selectors)
      unless selectors.all? { _1.start_with?("__") }
        Console.logger.error("#{component_class.display_name} has no stylesheet")
      end

      []
    end
  end

  StyleSheet = Data.define(:content_hash, :classes, :content) do
    def filename =
      "#{content_hash}.css"

    def [](*selectors)
      selectors.flatten.map do |selector|
        case selector
        in String
          selector
        in Hash
          self[*selector.filter { _2 }.keys]
        in Symbol
          classes.fetch(selector) do
            unless selector.start_with?("__")
              Console.logger.error("Could not find #{selector.inspect}")
              nil
            end
          end
        else
          nil
        end
      end.compact.uniq
    end
  end
end

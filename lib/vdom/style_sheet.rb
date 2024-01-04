# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

module VDOM
  NullStyleSheet =
    Data.define(:component_class) do
      def [](*class_names)
        unless class_names.compact.all? {
                 _1.start_with?("__") || String === _1
               }
          Console.logger.error(
            component_class.filename,
            "\e[31mNo stylesheet defined\e[0m"
          )
        end

        class_names.filter { String === _1 }
      end
    end

  StyleSheet =
    Data.define(:component_class, :content_hash, :classes, :content) do
      def filename = "#{content_hash}.css"

      def [](*class_names)
        class_names
          .compact
          .flatten
          .map do |class_name|
            case class_name
            in String
              class_name
            in Hash
              self[*class_name.filter { _2 }.keys]
            in Symbol
              classes.fetch(class_name) do
                unless class_name.start_with?("__")
                  available_class_names =
                    classes
                      .keys
                      .reject { _1.start_with?("__") }
                      .map { _1.to_s.prepend("  ") }
                      .join("\n")

                  Console.logger.error(
                    component_class.filename,
                    format(<<~MSG, class_name, available_class_names)
                      Could not find class: \e[1;31m.%s\e[0m
                      Available class names:
                      \e[1;33m%s\e[0m
                    MSG
                  )
                  nil
                end
              end
            else
              nil
            end
          end
          .compact
          .uniq
      end
    end
end

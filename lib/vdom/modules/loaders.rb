# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require_relative "../transformers/haml"
require_relative "../transformers/ruby"
require_relative "../transformers/css"
require_relative "mod"

module VDOM
  module Modules
    module Loaders
      module ComponentLoader
        Metadata = Data.define(:name, :path)

        def self.load(source, path)
          # puts "\e[3m SOURCE \e[0m"
          # puts "\e[33m#{source}\e[0m"

          source = Transformers::Haml.transform(source, path).output
          source = Transformers::Ruby.transform(source)

          puts "\e[3m TRANSFORMED \e[0m"
          puts "\e[32m#{source}\e[0m"

          mod = VDOM::Modules::Mod.new(source, path)
          component = mod::Export

          name = File.basename(path, ".*").freeze
          component.define_singleton_method(:title) { name }
          component.define_singleton_method(:display_name) { name }
          component.const_set(:COMPONENT_META, Metadata[name, path])

          if stylesheet = component.const_get(:Styles)
            if stylesheet.is_a?(VDOM::StyleSheet)
              mod.assets.push(
                Assets::Asset.build(
                  path + ".css",
                  stylesheet.content
                )
              )
            end
          end

          mod.assets.each { System.add_asset(_1) }

          # if stylesheet = component.const_get(Transformers::Haml::STYLES_CONST_NAME)
          #   Assets.instance.store(stylesheet.asset)
          # end
          #
          # if partials = component.const_get(Transformers::Haml::PARTIALS_CONST_NAME)
          #   partials.each { Assets.instance.store(_1.asset) }
          # end

          mod
        end
      end

      module StyleSheetLoader
        def self.load(source, path)
          VDOM::Modules::Mod.new(
            Transformers::CSS.transform(source, path),
            path
          )
        end
      end

      module ImageLoader
        def self.load(source, path)
          raise NotImplementedError
        end
      end

      def self.load(source, path)
        case File.extname(path)
        in ".haml"
          ComponentLoader.load(source, path)
        in ".css"
          StyleSheetLoader.load(source, path)
        in ".png" | ".jpg" | ".jpeg" | ".svg"
          ImageLoader.load(source, path)
        end
      end
    end
  end
end

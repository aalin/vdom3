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
        def self.load(source, path)
          # puts "\e[3m SOURCE \e[0m"
          # puts "\e[33m#{source}\e[0m"

          original_source = source
          source = Transformers::Haml.transform(source, path).output
          source = Transformers::Ruby.transform(source)

          source_map = SourceMap::SourceMap.parse(original_source, source)

          puts "\e[3m TRANSFORMED \e[0m"
          puts "\e[32m#{source.each_line.with_index(1).map { |l, i| format("%3d: %s", i, l) }.join}\e[0m"

          mod = VDOM::Modules::Mod.new(source, path)
          component = mod::Export

          name = File.basename(path, ".*").freeze
          component.define_singleton_method(:title) { name }
          component.define_singleton_method(:display_name) { name }
          component.const_set(
            :COMPONENT_META,
            Component::Metadata[name, path, source_map]
          )

          if stylesheet = component.const_get(:Styles)
            if stylesheet.is_a?(VDOM::StyleSheet)
              mod.assets.push(
                Assets::Asset.build(path + ".css", stylesheet.content)
              )
            end
          end

          mod.assets.each { System.add_asset(_1) }

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

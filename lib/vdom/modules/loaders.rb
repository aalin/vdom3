# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require_relative "../transformers/haml"
require_relative "../transformers/ruby"

module VDOM
  module Modules
    module Loaders
      Metadata = Data.define(:name, :path)

      def self.load(source, path)
        case File.extname(path)
        in ".haml"
          load_component(source, path)
        in ".css"
          load_stylesheet(source, path)
        end
      end

      def self.load_component(source, path)
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

        # if stylesheet = component.const_get(Transformers::Haml::STYLES_CONST_NAME)
        #   Assets.instance.store(stylesheet.asset)
        # end
        #
        # if partials = component.const_get(Transformers::Haml::PARTIALS_CONST_NAME)
        #   partials.each { Assets.instance.store(_1.asset) }
        # end

        mod
      end

      def self.load_stylesheet(source, path)
        raise NotImplementedError,
          "Use https://github.com/mayu-live/css"
      end
    end
  end
end

# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "pathname"
require_relative "transformers/haml"
require_relative "transformers/ruby"
require_relative "descriptors"
require_relative "css_units"

module VDOM
  module Component
    class Base
      H = VDOM::Descriptors::H

      def self.inspect =
        self::COMPONENT_META.name

      def self.import(filename)
        Modules::System.current.import(filename, caller.first)
      end

      def self.title = name[/[^:]+\z/]

      def initialize(**) = nil

      def props = @props ||= {}

      def mount = nil
      def render = nil

      private

      def async(task: Async::Task.current, &)
        task.async(&)
      end

      def update!(...)
        yield if block_given?
        rerender!
      end

      # this method will be defined on each component.
      def rerender! = nil
      # this method will be defined on each component.
      def emit!(event, **payload) = nil
    end

    class ComponentModule < Module
      using CSSUnits::Refinements

      def initialize(code, path) =
        instance_eval(code, path.to_s, 1)
    end

    Metadata = Data.define(:name, :path)

    module Registry
      HASH_LENGTH = 5

      def self.[](path)
        const_get(const_name_for_path(path))
      rescue
        nil
      end

      def self.[]=(path, component)
        const_set(const_name_for_path(path), component)
      end

      def self.const_name_for_path(path)
        name = path.to_s.upcase.gsub(/[^A-Z0-9]+/, "_")
        hash = Digest::SHA256.hexdigest(path.to_s)[0..HASH_LENGTH].upcase
        "MOD_#{name}__#{hash}"
      end
    end

    module Loader
      def self.load_file(filename, source_path = nil)
        path = Pathname.new(File.expand_path(filename, source_path)).freeze
        Registry[path] ||= load_component(File.read(path), path)
      end

      def self.load_component(source, path)
        # puts "\e[3m SOURCE \e[0m"
        # puts "\e[33m#{source}\e[0m"

        source = Transformers::Haml.transform(source, path).output
        source = Transformers::Ruby.transform(source)

        puts "\e[3m TRANSFORMED \e[0m"
        puts "\e[32m#{source}\e[0m"

        component_module = ComponentModule.new(source, path)
        component = component_module::Export

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

        component_module
      end
    end
  end
end

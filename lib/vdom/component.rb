# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "pathname"
require_relative "descriptors"
require_relative "css_units"
require_relative "modules"

module VDOM
  module Component
    class Base
      H = VDOM::Descriptors::H

      def self.import(filename) =
        Modules::System.import(
          filename,
          caller.first.split(":", 2).first
        )

      def self.display_name = name[/[^:]+\z/]
      def self.filename = self::FILENAME

      def self.merge_props(*sources)
        result =
          sources.reduce do |result, hash|
            result.merge(hash) do |key, old_value, new_value|
              case key
              in :class
                [old_value, new_value].flatten
              else
                new_value
              end
            end
          end

        if classes = result.delete(:class)
          classnames = self::Styles[*Array(classes)]

          unless classnames.empty?
            result[:class] = classnames.join(" ")
          end
        end

        result
      end

      def initialize(**) = nil

      def props = @props ||= {}

      def mount = nil
      def render = nil
      def unmount = nil

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
  end
end

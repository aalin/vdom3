# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

module VDOM
  module Descriptors
    Element = Data.define(:type, :children, :key, :slot, :props, :hash) do
      def self.[](type, *children, key: nil, slot: nil, **props) =
        new(
          type,
          children,
          key,
          slot,
          props,
          calculate_hash(type, key, slot, props)
        )

      def self.calculate_hash(type, key, slot, props) =
        [self, type, key, slot, type == :input && props[:type]].hash

      def self.or_string(descriptor) =
        if self === descriptor
          descriptor
        else
          (descriptor && descriptor.to_s) || nil
        end

      def same?(other) =
        if self.class === other && type == other.type && key == other.key
          if type == :input
            props[:type] == other.props[:type]
          else
            true
          end
        else
          false
        end
    end

    Text = Data.define(:content) do
      def to_s = content.to_s
      def same?(other) = self.class === other
    end

    Comment = Data.define(:content) do
      def to_s = content.to_s
      def same?(other) = self.class === other
    end

    StyleSheet = Data.define(:content)

    Callback = Data.define(:component, :method, :hash) do
      def self.[](component, method) =
        new(
          component,
          method,
          [self, component, method].hash
        )

      def same?(other) =
        self.class === other && component == other.component && method == other.method
    end

    def self.same?(a, b) =
      get_hash(a) == get_hash(b)

    def self.get_hash(descriptor)
      case descriptor
      in Element | Callback
        descriptor.hash
      else
        descriptor.class
      end
    end

    def self.group_by_slot(descriptors)
      descriptors.group_by do |descriptor|
        if descriptor in Descriptors::Element[slot:]
          slot
        else
          nil
        end
      end
    end

    module H
      extend self

      def [](type, *children, key: nil, slot: nil, **props) =
        Element[type, *children, key:, slot:, **props]

      def text(content) =
        Text[content]

      def comment(content) =
        Comment[content]

      def merge_props(*props) =
        props.reduce({}) { |acc, props| acc.merge(props) }

      def callback(component, method) =
        Callback[component, method]
    end
  end
end

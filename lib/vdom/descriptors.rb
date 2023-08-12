module VDOM
  module Descriptors
    Element = Data.define(:type, :children, :key, :slot, :props, :hash) do
      def self.[](type, *children, key: nil, slot: nil, **props) =
        new(
          type,
          normalize_children(children),
          key,
          slot,
          props,
          calculate_hash(type, key, slot, props)
        )

      def self.calculate_hash(type, key, slot, props) =
        [self.class, type, key, slot, type == :input && props[:type]].hash

      def self.normalize_children(children) =
        Array(children)
          .flatten
          .map { or_string(_1) }
          .compact
          .flatten

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
      def to_s = content
      def same?(other) = self.class === other
    end

    Comment = Data.define(:content) do
      def same?(other) = self.class === other
    end

    StyleSheet = Data.define(:content)

    def self.get_hash(descriptor)
      case descriptor
      when Element
        descriptor.hash
      else
        descriptor.class
      end
    end

    def self.same?(a, b) =
      get_hash(a) == get_hash(b)

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

      def merge_props(*props)
        props.reduce({}) { |acc, props| acc.merge(props) }
      end
    end
  end
end

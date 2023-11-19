# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

module VDOM
  module Modules
    class Mod < Module
      attr_reader :code
      attr_reader :path
      attr_reader :assets

      def initialize(code, path, assets = [])
        @code = code
        @path = path
        @assets = []
        System.register(path, self)
        instance_eval(@code, @path, 1)
      end

      def reevaluate
        remove_const(:Export) if const_defined?(:Export)
        instance_eval(@code, @path, 1)
      end

      def marshal_dump =
        [@code, @path, @assets]
      def marshal_load(data) =
        initialize(*data)
    end
  end
end

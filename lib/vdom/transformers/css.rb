# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# Released under AGPL-3.0

require "base64"
require "digest/sha2"

module VDOM
  module Transformers
    class CSS
      Result = Data.define(:filename, :source, :classes)

      def self.transform(source:, source_path:, source_line:)
        filename = Base64.urlsafe_encode64(Digest::SHA256.digest(source)) + ".css"
        classes = {}
        Result[filename, source, classes]
      end

      def self.merge_classnames(transform_results)
        classnames = Hash.new { |h, k| h[k] = Set.new }

        transform_results.each do |transform_result|
          transform_result.classes.each do |source, target|
            classnames[source].add(target)
          end
        end

        classnames.transform_values { _1.join(" ") }
      end
    end
  end
end

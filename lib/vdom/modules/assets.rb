# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "mime/types"
require "brotli"
require "digest/sha2"
require "base64"

module VDOM
  module Modules
    class Assets
      EncodedContent = Data.define(:encoding, :content) do
        def self.for_mime_type_and_content(mime_type, content) =
          if mime_type.binary?
            none(content)
          else
            brotli(content)
          end

        def self.none(content) =
          new(nil, content)

        def self.brotli(content) =
          new(:br, Brotli.deflate(content))
      end

      Asset = Data.define(:content_type, :content_hash, :encoded_content, :filename) do
        def self.build(filename, content)
          MIME::Types.type_for(filename) => [mime_type]

          encoded_content = EncodedContent.for_mime_type_and_content(mime_type, content)
          content_hash = Digest::SHA256.digest(encoded_content.content)
          content_type = mime_type.to_s

          filename = format(
            "%s.%s?%s",
            File.basename(filename, ".*"),
            mime_type.preferred_extension,
            Base64.urlsafe_encode64(content_hash, padding: false)
          )

          new(
            content_type:,
            content_hash:,
            encoded_content:,
            filename:,
          )
        end
      end

      def initialize =
        @assets = ObjectSpace::WeakMap.new

      def get(filename) =
        @assets[filename]

      def add(asset) =
        @assets[asset.filename] = asset
    end
  end
end

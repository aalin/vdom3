# frozen_string_literal: true

require "nanoid"
require "msgpack"
require "zlib"

module VDOM
  module EventStream
    CONTENT_TYPE = "application/vnd.mayu.event-stream"
    CONTENT_ENCODING = "deflate-raw"

    class Writer < Async::HTTP::Body::Writable
      def initialize(...)
        super
        @deflate =
            Zlib::Deflate.new(
              Zlib::BEST_COMPRESSION,
              -Zlib::MAX_WBITS,
              Zlib::MAX_MEM_LEVEL,
              Zlib::HUFFMAN_ONLY
            )
        @wrapper = MsgPackWrapper.new
      end

      def write(buf)
        buf
          .then { PatchSet[_1].to_a }
          .then { @wrapper.pack(_1) }
          .then { @deflate.deflate(_1, Zlib::SYNC_FLUSH) }
          .then { super(_1) }
      end


      def close(reason = nil)
        @queue.enqueue(@deflate.flush(Zlib::FINISH)) rescue nil
        @deflate.close rescue nil
        super
      end
    end

    Blob = Data.define(:data) do
      def self.from_msgpack_ext(data) =
        new(data)
      def to_msgpack_ext =
        data
    end

    class MsgPackWrapper < MessagePack::Factory
      def initialize
        super()

        self.register_type(0x01, Blob)
      end
    end

    PatchSet = Data.define(:id, :patches) do
      def self.[](patches) =
        new(Nanoid.generate, [patches].flatten)

      def to_a
        patches.map do |patch|
          [patch.class.name[/[^:]+\z/], *patch.deconstruct]
        end
      end
    end
  end
end

require "zlib"

module VDOM
  module Compression
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
      end

      def write(buf) =
        super(@deflate.deflate(buf, Zlib::SYNC_FLUSH))

      def close(error = nil)
        @queue.enqueue(@deflate.flush(Zlib::FINISH))
        @deflate.close
        super
      end
    end
  end
end

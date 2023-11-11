# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "time"
require "digest/sha2"
require "openssl"
require "securerandom"
require "brotli"

module VDOM
  class MessageCipher
    DEFAULT_TTL_SECONDS = 10

    Message = Data.define(:iss, :exp, :payload)

    class Error < StandardError
    end
    class ExpiredError < Error
    end
    class IssuedInTheFutureError < Error
    end
    class EncryptError < Error
    end
    class DecryptError < Error
    end
    class InvalidHMACError < Error
    end

    def initialize(key:, ttl: DEFAULT_TTL_SECONDS)
      raise ArgumentError, "ttl must be positive" unless ttl.positive?
      @default_ttl_seconds = ttl
      @key = Digest::SHA256.digest(key)
    end

    def dump(payload, auth_data: "", ttl: @default_ttl_seconds)
      raise ArgumentError, "ttl must be positive" unless ttl.positive?
      now = Time.now.to_f
      message = { iss: now, exp: now + ttl, payload: Marshal.dump(payload) }
      encode_message(message, auth_data:)
    end

    def load(data, auth_data: "")
      Marshal.load(decode_message(data, auth_data:))
    end

    private

    def encode_message(message, auth_data: "")
      message
        .then { Marshal.dump(_1) }
        .then { prepend_hmac(_1) }
        .then { Brotli.deflate(_1) }
        .then { encrypt(_1, auth_data:) }
    end

    def decode_message(message, auth_data: "")
      message
        .then { decrypt(_1, auth_data:) }
        .then { Brotli.inflate(_1) }
        .then { validate_hmac(_1) }
        .then { Marshal.load(_1) }
        .tap { validate_times(_1) }
        .fetch(:payload)
    end

    def prepend_hmac(input)
      hmac = Digest::SHA256.digest(input)
      input.prepend(hmac)
    end

    def validate_hmac(input)
      hmac, message = input.unpack("a32 a*")

      unless OpenSSL.fixed_length_secure_compare(
               hmac,
               Digest::SHA256.digest(message.to_s)
             )
        raise InvalidHMACError
      end

      message.to_s
    end

    def validate_times(message)
      message => { iss:, exp: }
      now = Time.now.to_f
      validate_iss(now, iss)
      validate_exp(now, exp)
    end

    def validate_iss(now, iss)
      return if iss < now

      raise IssuedInTheFutureError,
            "The message was issued at #{Time.at(iss).iso8601}, which is in the future"
    end

    def validate_exp(now, exp)
      return if exp > now

      raise ExpiredError,
            "The message expired at #{Time.at(exp).iso8601}, which is in the past"
    end

    def encrypt(message, auth_data: "")
      cipher = OpenSSL::Cipher.new("aes-256-gcm")
      cipher.encrypt
      salt = SecureRandom.random_bytes(8)
      cipher.key = generate_key(salt)
      cipher.iv = iv = cipher.random_iv
      cipher.auth_data = auth_data
      cipher_text = cipher.update(message) + cipher.final
      auth_tag = cipher.auth_tag
      [auth_tag.bytesize, auth_tag, salt, iv, cipher_text].pack("C a* a* a* a*")
    rescue OpenSSL::Cipher::CipherError
      raise EncryptError
    end

    def decrypt(data, auth_data: "")
      data.unpack("C a*") => [Integer => auth_tag_len, String => data]

      data.unpack("a#{auth_tag_len} a8 a12 a*") => [
        auth_tag,
        salt,
        iv,
        cipher_text
      ]

      cipher = OpenSSL::Cipher.new("aes-256-gcm")
      cipher.iv = iv
      cipher.key = generate_key(salt)
      cipher.auth_data = auth_data
      cipher.auth_tag = auth_tag
      cipher.update(cipher_text) + cipher.final
    rescue NoMatchingPatternError
      raise DecryptError
    rescue OpenSSL::Cipher::CipherError
      raise DecryptError
    end

    def generate_key(salt)
      OpenSSL::KDF.scrypt(
        @key,
        salt:, # Salt.
        N: 2**14, # CPU/memory cost parameter. This must be a power of 2.
        r: 8, # Block size parameter.
        p: 1, # Parallelization parameter
        length: 32 # Length in octets of the derived key
      )
    end
  end
end

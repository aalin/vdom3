# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "minitest/autorun"

require_relative "message_cipher"

class VDOM::MessageCipher::Test < Minitest::Test
  def test_dump_and_load
    message_cipher = VDOM::MessageCipher.new(key: "test")

    dumped = message_cipher.dump("hello")
    loaded = message_cipher.load(dumped)

    assert_equal("hello", loaded)
  end

  def test_dump_and_load_object
    message_cipher = VDOM::MessageCipher.new(key: "test")

    object = {
      foo: "hello",
      bar: {
        baz: [123.456, :asd]
      }
    }

    dumped = message_cipher.dump(object)
    loaded = message_cipher.load(dumped)

    assert_equal(object, loaded)
  end

  def test_issued_in_the_future
    now = Time.now
    message_cipher = VDOM::MessageCipher.new(key: "test")

    dumped = message_cipher.dump("hello")

    Time.stub(:now, Time.at(Time.now - 1)) do
      assert_raises(VDOM::MessageCipher::IssuedInTheFutureError) do
        message_cipher.load(dumped)
      end
    end
  end

  def test_expiration
    now = Time.now
    message_cipher = VDOM::MessageCipher.new(key: "test")
    dumped = message_cipher.dump("hello")

    Time.stub(:now, Time.at(Time.now + VDOM::MessageCipher::DEFAULT_TTL_SECONDS)) do
      assert_raises(VDOM::MessageCipher::ExpiredError) do
        message_cipher.load(dumped)
      end
    end
  end

  def test_invalid_key
    cipher1 = VDOM::MessageCipher.new(key: "foo")
    cipher2 = VDOM::MessageCipher.new(key: "bar")

    dumped = cipher1.dump("hello")

    assert_raises(VDOM::MessageCipher::DecryptError) do
      cipher2.load(dumped)
    end
  end
end

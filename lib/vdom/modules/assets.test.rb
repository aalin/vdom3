# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "minitest/autorun"

require_relative "assets"

class VDOM::Modules::Assets::Test < Minitest::Test
  def test_asset
    asset = VDOM::Modules::Assets::Asset.build("/path/to/foo.txt", "content")

    assert_equal(
      "text/plain",
      asset.content_type
    )
    assert_equal(
      :br,
      asset.encoded_content.encoding
    )
    assert_equal(
      "content",
      Brotli.inflate(asset.encoded_content.content)
    )
    assert_equal(
      "/path/to/foo.txt?yqy-cFH3rN6EyrcsWbBdog-NE1tHRkLWWO1sdhQVMNk",
      asset.filename
    )
    assert_equal(
      Digest::SHA256.digest("content"),
      asset.content_hash
    )
  end

  def test_asset
    asset = VDOM::Modules::Assets::Asset.build("/path/to/foo.png", "content")

    assert_equal(
      "image/png",
      asset.content_type
    )
    assert_nil(
      asset.encoded_content.encoding
    )
    assert_equal(
      "content",
      asset.encoded_content.content
    )
    assert_equal(
      "/path/to/foo.png?7XACtDnprIRfIjV9giusFERzD722AW0-yUMil7nsn3M",
      asset.filename
    )
    assert_equal(
      Digest::SHA256.digest("content"),
      asset.content_hash
    )
  end
end

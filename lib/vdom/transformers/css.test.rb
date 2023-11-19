require "minitest/autorun"
require_relative "css"

class VDOM::Transformers::CSS::Test < Minitest::Test
  def test_transform
    transformed = VDOM::Transformers::CSS.transform("/app/components/Hello.css", <<~CSS)
      ul { background: rgb(0 128 255 / 50%); }
      li { border: 1px solid #f0f; }
      .foo { border: 1px solid #f0f; }
      .bar { background: url("./bar.png"); }
    CSS

    assert_equal <<~RUBY.chomp, transformed.chomp
      class self::Export < VDOM::StyleSheet::Base
        Dep_KhO7Yq = import "./bar.png"
        CODE = <<CSS
      .\\\\/app\\\\/components\\\\/Hello_ul\\\\?h5fQnDO8 {
        background: #0080ff80;
      }

      .\\\\/app\\\\/components\\\\/Hello_li\\\\?h5fQnDO8 {
        border: 1px solid #f0f;
      }

      .\\\\/app\\\\/components\\\\/Hello\\\\.foo\\\\?h5fQnDO8 {
        border: 1px solid #f0f;
      }

      .\\\\/app\\\\/components\\\\/Hello\\\\.bar\\\\?h5fQnDO8 {
        background: url("\#{encode_uri(Dep_KhO7Yq.public_path)}");
      }
      CSS
        CONTENT_HASH = \"bQfOROhDmc-nBmWHPAum9htk6G-iGTvhD6gZ0uuSBaw\"
        CLASSES = {
          __li: \"/app/components/Hello_li?h5fQnDO8\",
          __ul: \"/app/components/Hello_ul?h5fQnDO8\",
          bar: \"/app/components/Hello.bar?h5fQnDO8\",
          foo: \"/app/components/Hello.foo?h5fQnDO8\"
        }
      end
    RUBY
  end

  def test_transform_inline
    ast = VDOM::Transformers::CSS.transform_inline("/app/components/Hello.css", <<~CSS)
      ul { background: rgb(0 128 255 / 50%); }
      li { border: 1px solid #f0f; }
      .foo { border: 1px solid #f0f; }
      .bar { background: url("./bar.png"); }
    CSS

    transformed = SyntaxTree::Formatter.format("", ast)

    assert_equal <<~RUBY.chomp, transformed.chomp
      Dep_KhO7Yq = import "./bar.png"
      VDOM::StyleSheet[
        component_class: self,
        content_hash: "bQfOROhDmc-nBmWHPAum9htk6G-iGTvhD6gZ0uuSBaw",
        classes: {
          __li: "/app/components/Hello_li?h5fQnDO8",
          __ul: "/app/components/Hello_ul?h5fQnDO8",
          bar: "/app/components/Hello.bar?h5fQnDO8",
          foo: "/app/components/Hello.foo?h5fQnDO8"
        },
        content: <<CSS
      .\\\\/app\\\\/components\\\\/Hello_ul\\\\?h5fQnDO8 {
        background: #0080ff80;
      }

      .\\\\/app\\\\/components\\\\/Hello_li\\\\?h5fQnDO8 {
        border: 1px solid #f0f;
      }

      .\\\\/app\\\\/components\\\\/Hello\\\\.foo\\\\?h5fQnDO8 {
        border: 1px solid #f0f;
      }

      .\\\\/app\\\\/components\\\\/Hello\\\\.bar\\\\?h5fQnDO8 {
        background: url("\#{encode_uri(Dep_KhO7Yq.public_path)}");
      }
      CSS
      ]
    RUBY

    puts transformed
  end
end

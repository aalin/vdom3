# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# Released under AGPL-3.0

require "base64"
require "digest/sha2"
require "mayu/css"
require "syntax_tree"
require_relative "../style_sheet"

module VDOM
  module Transformers
    class CSS
      include SyntaxTree::DSL

      DEPENDENCY_CONST_PREFIX = "Dep_"
      CODE_CONST_NAME = "CODE"
      CONTENT_HASH_CONST_NAME = "CONTENT_HASH"

      def self.transform(source_path, source)
        Mayu::CSS.transform(source_path, source)
          .then { new(_1).build_ast }
          .then { SyntaxTree::Formatter.format("", _1) }
      end

      def initialize(parse_result)
        @parse_result = parse_result
      end

      def build_ast
        ClassDeclaration(
          ConstPathRef(
            VarRef(Kw("self")),
            Const("Export")
          ),
          ConstPathRef(
            VarRef(Const("VDOM")),
            ConstPathRef(
              VarRef(Const("StyleSheet")),
              Const("Base")
            )
          ),
          BodyStmt(Statements([
            *@parse_result.dependencies.map do |dep|
              dep => { placeholder:, url: }

              Assign(
                VarField(Const(DEPENDENCY_CONST_PREFIX + placeholder)),
                Command(
                  Ident("import"),
                  Args([
                    StringLiteral([TStringContent(url)], '"'),
                  ]),
                  nil
                ),
              )
            end,
            Assign(
              VarField(Const(CODE_CONST_NAME)),
              Heredoc(
                HeredocBeg("<<CSS"),
                HeredocEnd("CSS"),
                nil,
                build_code_heredoc
              )
            ),
            Assign(
              VarField(Const(CONTENT_HASH_CONST_NAME)),
              CallNode(
                ConstPathRef(
                  VarRef(Const("Digest")),
                  Const("SHA256")
                ),
                Period("."),
                Ident("digest"),
                ArgParen(Args([
                  VarRef(Const(CODE_CONST_NAME))
                ]))
              )
            ),
            Assign(
              VarField(Const("CLASSES")),
              HashLiteral(
                LBrace("{"),
                @parse_result.classes.sort_by(&:first).map do |key, value|
                  Assoc(
                    Label("#{key}:"),
                    StringLiteral(
                      [TStringContent(value.to_s)],
                      '"'
                    )
                  )
                end +
                @parse_result.elements.sort_by(&:first).map do |key, value|
                  Assoc(
                    Label("__#{key}:"),
                    StringLiteral(
                      [TStringContent(value.to_s)],
                      '"'
                    )
                  )
                end
              )
            ),
          ]), nil, nil, nil, nil)
        )
      end

      private

      def build_code_heredoc
        parts = []
        remains = @parse_result.code

        @parse_result.dependencies.map do |dep|
          dep => { placeholder: }
          remains.split(placeholder, 2) => [part, remains]

          parts.push(
            TStringContent(part),
            StringEmbExpr(
              Statements([
                CallNode(
                  nil,
                  nil,
                  Ident("encode_uri"),
                  ArgParen(
                    Args([
                      CallNode(
                        VarRef(Const(DEPENDENCY_CONST_PREFIX + placeholder)),
                        Period("."),
                        Ident("public_path"),
                        nil
                      )
                    ])
                  )
                ),
              ])
            )
          )
        end

        unless remains.empty?
          parts.push(TStringContent(remains))
        end

        parts
      end
    end
  end
end

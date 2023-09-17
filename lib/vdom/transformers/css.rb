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

      def self.transform(source_path, source)
        Mayu::CSS.transform(source_path, source)
          .then { new(_1).build_class_ast }
          .then { SyntaxTree::Formatter.format("", _1) }
      end

      def self.transform_inline(source_path, source, **)
        Mayu::CSS.transform(source_path, source)
          .then { new(_1, **).build_inline_ast }
      end

      def initialize(parse_result, dependency_const_prefix: "Dep_", code_const_name: "CODE", content_hash_const_name: "CONTENT_HASH")
        @parse_result = parse_result
        @dependency_const_prefix = dependency_const_prefix
        @code_const_name = code_const_name
        @content_hash_const_name = content_hash_const_name
      end

      def build_inline_ast
        Statements([
          *build_imports,
          ARef(
            ConstPathRef(
              VarRef(Const("VDOM")),
              Const("StyleSheet")
            ),
            Args([
              BareAssocHash([
                Assoc(
                  Label("content_hash:"),
                  build_content_hash_string
                ),
                Assoc(
                  Label("classes:"),
                  build_classes_hash
                ),
                Assoc(
                  Label("content:"),
                  build_code_heredoc,
                )
              ])
            ])
          )
        ])
      end

      def build_class_ast
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
          BodyStmt(build_statements_ast, nil, nil, nil, nil)
        )
      end

      def build_statements_ast
        Statements([
          *build_imports,
          Assign(
            VarField(Const(@code_const_name)),
            build_code_heredoc
          ),
          Assign(
            VarField(Const(@content_hash_const_name)),
            build_content_hash_string
          ),
          Assign(
            VarField(Const("CLASSES")),
            build_classes_hash
          ),
        ])
      end

      private

      def build_imports
        @parse_result.dependencies.map do |dep|
          dep => { placeholder:, url: }

          Assign(
            VarField(Const(@dependency_const_prefix + placeholder)),
            build_import(url)
          )
        end
      end

      def build_import(url)
        Command(
          Ident("import"),
          Args([
            StringLiteral([TStringContent(url)], '"'),
          ]),
          nil
        )
      end

      def build_content_hash_string
        StringLiteral(
          [TStringContent(
            @parse_result.code
              .then { Digest::SHA256.digest(_1) }
              .then { Base64.urlsafe_encode64(_1, padding: false) }
          )],
          '"'
        )
      end

      def build_classes_hash
        HashLiteral(
          LBrace("{"),
          build_classes_assocs,
        )
      end

      def build_classes_assocs
        {
          **@parse_result.classes,
          **@parse_result.elements.transform_keys { "__#{_1}" }
        }.sort_by(&:first).map do |key, value|
          Assoc(
            Label("#{key}:"),
            StringLiteral(
              [TStringContent(value.to_s)],
              '"'
            )
          )
        end
      end

      def build_code_heredoc
        Heredoc(
          HeredocBeg("<<CSS"),
          HeredocEnd("CSS"),
          nil,
          build_code_heredoc_inner
        )
      end

      def build_code_heredoc_inner
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
                        VarRef(Const(@dependency_const_prefix + placeholder)),
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

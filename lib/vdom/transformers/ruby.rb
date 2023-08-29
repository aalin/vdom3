# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "syntax_tree"
require_relative "mutation_visitor"
require_relative "xml_utils"

module VDOM
  module Transformers
    class Ruby
      class FrozenStringLiteralsVisitor < SyntaxTree::Visitor
        def visit_program(node)
          node.copy(statements: visit(node.statements))
        end

        def visit_statements(node)
          node.copy(body: [
            SyntaxTree::Comment.new(
              value: "# frozen_string_literal: true",
              inline: false,
              location: node.location
            ),
            *node.body,
          ])
        end
      end

      include SyntaxTree::DSL

      COLLECTIONS = {
        SyntaxTree::IVar => "state",
        SyntaxTree::GVar => "props",
      }

      def self.transform(source)
        transformer = new
        SyntaxTree.parse(source)
          .accept(transformer.heredoc_html)
          .then { transformer.wrap_in_class(_1) }
          .accept(transformer.frozen_strings)
          .then { SyntaxTree::Formatter.format(source, _1) }
      end

      def frozen_strings = FrozenStringLiteralsVisitor.new

      def wrap_in_class(program)
        statements =
          Statements([
            ClassDeclaration(
              ConstPathRef(
                VarRef(Ident("self")),
                Const("Export")
              ),
              ConstPathRef(
                VarRef(Const("VDOM")),
                ConstPathRef(
                  VarRef(Const("Component")),
                  Const("Base")
                )
              ),
              BodyStmt(
                Statements([using_statements, program.statements.body].flatten),
                nil, nil, nil, nil),
            )
          ])
        program.copy(statements:)
      end

      def using_statements
        [
          Command(
            Ident("using"),
            Args([
              ConstPathRef(
                VarRef(Const("CSSUnits")),
                Const("Refinements")
              )
            ]),
          nil
          )
        ]
      end

      def heredoc_html
        MutationVisitor.new.tap do |visitor|
          visitor.mutate("XStringLiteral | Heredoc[beginning: HeredocBeg[value: '<<~HTML']]") do |node|
            tokenizer = XMLUtils::Tokenizer.new

            node.parts.flat_map do |child|
              case child
              in SyntaxTree::TStringContent
                tokenizer.tokenize(child.value)
              in SyntaxTree::StringEmbExpr
                tokenizer.T(:statements, child.statements.accept(visitor))
              end
            end

            parser = XMLUtils::Parser.new
            parser.parse(tokenizer.tokens.dup)

            statements =
              parser
                .tokens
                .map { xml_token_to_ast_node(_1) }
                .compact

            SyntaxTree::Formatter.format("", Statements(statements))

            Statements(statements)
          end
        end
      end

      def xml_token_to_ast_node(token)
        case token
        in type: :tag, value: { name:, attrs:, children: }
          args = [
            SymbolLiteral(Ident(name.to_sym)),
            *children.map { xml_token_to_ast_node(_1) },
            unless attrs.empty?
              BareAssocHash(
                attrs.map { xml_token_to_ast_node(_1) }
              )
            end
          ].compact

          ARef(VarRef(Const("H")), Args(args))
        in type: :attr, value: { name:, value: }
          Assoc(
            StringLiteral([TStringContent(name)], '"'),
            xml_token_to_ast_node(value)
          )
        in type: :attr_value, value:
          StringLiteral([TStringContent(value)], '"')
        in type: :var_ref, value: /\A@(.*)/
          ARef(
            call_self("state"),
            Args([SymbolLiteral(Ident($~[1]))]),
          )
        in type: :var_ref, value: /\A\$(.*)/
          ARef(
            call_self("props"),
            Args([SymbolLiteral(Ident($~[1]))]),
          )
        in type: :newline
          nil
        in type: :string, value:
          StringLiteral([TStringContent(value)], '"')
        in type: :statements, value:
          case value.body
          in []
            nil
          in [first]
            first
          in [*many]
            Begin(BodyStmt(value))
          end
        end
      end

      private

      def call_html(parts)
        call_self(:html, ArgParen(Args([StringLiteral(parts, '"')])))
      end

      def call_self(method, args = nil)
        CallNode(
          VarRef(Kw("self")),
          Period("."),
          Ident(method),
          args
        )
      end

      def update(nodes)
        MethodAddBlock(
          call_self("update"),
          BlockNode(
            Kw("{"),
            nil,
            Statements(Array(nodes))
          )
        )
      end

      def aref(node)
        ARef(
          call_self(COLLECTIONS.fetch(node.class)),
          Args([SymbolLiteral(Ident(strip_var_prefix(node.value)))]),
        )
      end

      def aref_field(node)
        ARefField(
          call_self(COLLECTIONS.fetch(node.class)),
          Args([SymbolLiteral(Ident(strip_var_prefix(node.value)))]),
        )
      end

      def strip_var_prefix(str)
        str
          .delete_prefix("@")
          .delete_prefix("$")
      end
    end
  end
end

if __FILE__ == $0
  source = <<~RUBY
    def render
      H[:div,
        H[:p, "Hello world"]
      ]
    end
  RUBY

  puts "\e[3m SOURCE: \e[0m"
  puts source
  puts "\e[3m TRANSFORMED: \e[0m"
  puts VDOM::Transformers::Ruby.transform(source)
end

# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require_relative "../transformers/haml"
require_relative "../transformers/ruby"
require_relative "../transformers/css"
require_relative "mod"

module VDOM
  module Modules
    module Loaders
      module ComponentLoader
        Pos = Data.define(:line, :column)

        SourceMap =
          Data.define(:input, :output, :mappings) do
            MatchingLine =
              Data.define(:id, :line, :old_line, :new_line, :text) do
                def self.match(new_line, line)
                  if line.match(
                       /\A\s+# SourceMapMark:([[:alnum:]]+):(\d+):([a-zA-Z0-9=]+)/
                     ) in [id, line_no, text]
                    new(
                      id,
                      line,
                      line_no.to_i,
                      new_line,
                      Base64.urlsafe_decode64(text)
                    )
                  end
                end
              end

            def self.parse(input, output)
              mappings = {}

              input_lines = input.each_line.to_a
              output_lines = output.each_line.to_a

              found =
                output
                  .each_line
                  .with_index(1)
                  .map { |line, i| MatchingLine.match(i, line) }
                  .compact
                  .flatten

              [*found, nil].each_cons(2) do |curr, succ|
                if curr.text == ":ruby"
                  next
                else
                  line_no = curr.old_line
                  column = input_lines[line_no.pred].to_s.index(curr.text) || 0
                  p [curr.new_line + 1, line_no, curr.text]
                  mappings[curr.new_line + 1] = Pos[line_no, column]
                end
              end

              new(input, output, mappings)
            end

            def rewrite_exception(file, e)
              new_backtrace =
                e.backtrace.map do |entry|
                  re = /\A#{Regexp.escape(file)}:(\d+):(.*)/
                  if match = entry.match(re)
                    line_no = match[1].to_i

                    if mapping = mappings[line_no]
                      [file, mapping.line, match[2]].join(":")
                    else
                      entry
                    end
                  else
                    entry
                  end
                end

              e.set_backtrace(new_backtrace.first(10))
            end
          end

        def self.load(source, path)
          # puts "\e[3m SOURCE \e[0m"
          # puts "\e[33m#{source}\e[0m"

          original_source = source
          source = Transformers::Haml.transform(source, path).output
          source = Transformers::Ruby.transform(source)

          source_map = SourceMap.parse(original_source, source)

          puts "\e[3m TRANSFORMED \e[0m"
          puts "\e[32m#{source.each_line.with_index(1).map { |l, i| format("%3d: %s", i, l) }.join}\e[0m"

          mod = VDOM::Modules::Mod.new(source, path)
          component = mod::Export

          name = File.basename(path, ".*").freeze
          component.define_singleton_method(:title) { name }
          component.define_singleton_method(:display_name) { name }
          component.const_set(
            :COMPONENT_META,
            Component::Metadata[name, path, source_map]
          )

          if stylesheet = component.const_get(:Styles)
            if stylesheet.is_a?(VDOM::StyleSheet)
              mod.assets.push(
                Assets::Asset.build(path + ".css", stylesheet.content)
              )
            end
          end

          mod.assets.each { System.add_asset(_1) }

          mod
        end
      end

      module StyleSheetLoader
        def self.load(source, path)
          VDOM::Modules::Mod.new(
            Transformers::CSS.transform(source, path),
            path
          )
        end
      end

      module ImageLoader
        def self.load(source, path)
          raise NotImplementedError
        end
      end

      def self.load(source, path)
        case File.extname(path)
        in ".haml"
          ComponentLoader.load(source, path)
        in ".css"
          StyleSheetLoader.load(source, path)
        in ".png" | ".jpg" | ".jpeg" | ".svg"
          ImageLoader.load(source, path)
        end
      end
    end
  end
end

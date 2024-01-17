module VDOM
  module Modules
    module SourceMap
      Mark =
        Data.define(:line, :text) do
          def to_comment
            "SourceMapMark:#{line}:#{Base64.urlsafe_encode64(text)}"
          end
        end

      Pos = Data.define(:line, :column)

      MatchingLine =
        Data.define(:line, :old_line, :new_line, :text) do
          def self.match(new_line, line)
            if line.match(/\A\s+# SourceMapMark:(\d+):([[:alnum:]_]+)/) in [
                 line_no,
                 text
               ]
              new(line, line_no.to_i, new_line, Base64.urlsafe_decode64(text))
            end
          end
        end

      SourceMap =
        Data.define(:input, :output, :mappings) do
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
              line_no = curr.old_line
              column = input_lines[line_no.pred].to_s.index(curr.text) || 0
              p [curr.new_line + 1, line_no, curr.text]
              mappings[curr.new_line + 1] = Pos[line_no, column]
            end

            new(input, output, mappings)
          end

          def rewrite_exception(file, e)
            new_backtrace =
              e.backtrace.map do |entry|
                re = /\A#{Regexp.escape(file)}:(\d+):(.*)/

                if match = entry.match(re)
                  line_no = match[1].to_i

                  if mapping =
                       mappings.reject { |k, v| k > line_no }.to_a.last&.last
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
    end
  end
end

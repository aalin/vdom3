# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

module VDOM
  module Runtime
    module Components
      class HTML < Component::Base
        def render
          H[:html, H[:slot, key: "content"], @props[:descriptor], lang: @props[:lang]]
        end
      end

      class Head < Component::Base
        def render
          @props => { session_id:, main_js:, user_tags: }

          H[
            :__head,
            H[:meta, charset: "utf-8"],
            *user_tags,
            # H[:slot, key: "user_tags"],
            script_tag,
            *stylesheet_links
          ]
        end

        def stylesheet_links
          @props[:assets]
            .map do |asset|
              if asset.content_type == "text/css"
                href = File.join("/.mayu/assets", asset.filename)
                puts "\e[3;35m#{href}\e[0m"

                H[:link, key: href, rel: "stylesheet", href:]
              end
            end
            .compact
        end

        def script_tag
          H[
            :script,
            type: "module",
            src: @props[:main_js],
            async: true,
            key: "main_js"
          ]
        end
      end
    end
  end
end

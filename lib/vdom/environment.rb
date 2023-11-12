# frozen_string_literal: true

module VDOM
  Environment = Data.define(:root_path, :client_path, :main_js) do
    def self.setup(root_path:, client_path:)
      main_js =
        File.read(File.join(client_path, "entries.json"))
          .then { JSON.parse(_1) }
          .fetch("main")

      new(
        root_path:,
        client_path:,
        main_js:,
      )
    end
  end
end

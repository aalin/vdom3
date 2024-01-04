# frozen_string_literal: true
#
# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require_relative "encrypted_marshal"

module VDOM
  Environment =
    Data.define(
      :root_path,
      :app_path,
      :client_path,
      :main_js,
      :encrypted_marshal
    ) do
      def self.setup(root_path:, app_path:, secret_key:)
        client_path = File.join(root_path, "client", "dist")

        main_js =
          File
            .read(File.join(client_path, "entries.json"))
            .then { JSON.parse(_1) }
            .fetch("main")

        encrypted_marshal = EncryptedMarshal.new(secret_key)

        new(root_path:, app_path:, client_path:, main_js:, encrypted_marshal:)
      end
    end
end

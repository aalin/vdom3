# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

module VDOM
  module Runtime
    module Patches
      Initialize = Data.define(:id_tree)

      CreateElement = Data.define(:id, :type)
      CreateTextNode = Data.define(:id, :content)
      CreateComment = Data.define(:id, :content)

      ReplaceChildren = Data.define(:parent_id, :child_ids)

      RemoveNode = Data.define(:id)

      SetAttribute = Data.define(:id, :name, :value)
      RemoveAttribute = Data.define(:id, :name)

      SetClassName = Data.define(:id, :class_name)

      SetListener = Data.define(:id, :name, :listener_id)
      RemoveListener = Data.define(:id, :name, :listener_id)

      SetCSSProperty = Data.define(:id, :name, :value)
      RemoveCSSProperty = Data.define(:id, :name)

      SetTextContent = Data.define(:id, :content)
      ReplaceData = Data.define(:id, :offset, :count, :data)
      InsertData = Data.define(:id, :offset, :data)
      DeleteData = Data.define(:id, :offset, :count)

      AddStyleSheet = Data.define(:filename)

      Transfer = Data.define(:payload)

      Ping = Data.define(:timestamp)

      Event = Data.define(:event, :payload)
    end
  end
end

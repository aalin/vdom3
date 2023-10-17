# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "filewatcher"
require "pathname"

require_relative "component"
require_relative "modules/dependency_graph"
require_relative "modules/dot_exporter"
require_relative "modules/loaders"
require_relative "modules/mod"
require_relative "modules/registry"
require_relative "modules/resolver"
require_relative "modules/system"
require_relative "modules/watcher"

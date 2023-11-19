# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

module VDOM
  module Modules
    class Watcher
      def self.run(system, task: Async::Task.current)
        task.async do
          Filewatcher
            .new([system.root])
            .watch do |changes|
              changes.each do |path, event|
                relative_from_root = system.relative_from_root(path)

                if event in :created | :deleted | :updated
                  $stderr.puts "\e[33m#{event}: #{relative_from_root}\e[0m"
                  system.send(event, relative_from_root)
                else
                  $stderr.puts "\e[31mUnhandled event: #{event}: #{relative_from_root}\e[0m"
                end
              end
            end
        end
      end
    end
  end
end

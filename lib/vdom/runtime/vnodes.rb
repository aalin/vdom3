# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "cgi"
require "securerandom"

require "async/barrier"
require "async/queue"

require_relative "../descriptors"
require_relative "../component"

require_relative "components"
require_relative "patches"
require_relative "inline_style"

module VDOM
  module Runtime
    module VNodes
      INCLUDE_DEBUG_ID = false

      class Unmount < Exception
      end

      IdNode =
        Data.define(:id, :name, :children) do
          def self.[](id, name, children = nil)
            new(id, name, children)
          end

          def serialize
            if c = children
              { id:, name:, children: c.flatten.compact.map(&:serialize) }
            else
              { id:, name: }
            end
          end
        end

      class Base
        class AlreadyStartedError < StandardError
        end

        def self.generate_id = SecureRandom.alphanumeric(10)

        def self.run(...)
          node = start(...)
          yield node
        ensure
          node&.stop
        end

        attr_reader :id
        attr_reader :descriptor
        attr_reader :root
        attr_reader :parent

        def initialize(descriptor, parent: nil)
          @descriptor = descriptor
          @parent = parent
          @root = parent.root
          @id = Base.generate_id
          @incoming = Async::Queue.new
        end

        def start(...)
          if @task
            raise AlreadyStartedError,
                  "#{self.class.name} has already been started"
          end

          @task =
            async do
              Fiber[CURRENT_KEY] = self
              run(...)
            end

          self
        end

        def run(...)
          raise NotImplementedError,
                "#{self.class.name}##{__method__} has not been implemented"
        end

        def resume(*args)
          @incoming.dequeue until @incoming.empty?
          @incoming.enqueue(args)
        end

        def stop
          @task&.stop
        end

        def after_initialize = nil

        def patch(&)
          @root.patch(&)
        end

        def marshal_dump = [@id, @parent, @descriptor, @instance, @children]

        def closest(type)
          if type === self
            self
          else
            @parent.closest(type)
          end
        end

        def traverse(&) = yield self

        def inspect =
          "#<#{self.class.name}##{@id} descriptor=#{@descriptor.inspect}>"

        def dom_ids = [@id]
        def dom_id_tree = IdNode[@id, dom_node_name]

        def mount = nil
        def unmount = nil

        def add_asset(asset) = @parent.add_asset(asset)

        def task = Async::Task.current

        def update_children_order = @parent.update_children_order

        def parent_element_id = @parent.parent_element_id

        def get_slotted(name) = @parent.get_slotted(name)

        def component_path = @parent.component_path

        private

        def receive(&)
          if block_given?
            yield(*receive) while true
          else
            @incoming.dequeue
          end
        end
      end

      class VAny < Base
        def initialize(...)
          super(...)
          descriptor = unwrap(@descriptor)
          @child =
            descriptor_to_node_type(unwrap(descriptor)).new(
              descriptor,
              parent: self
            )
        end

        def mount = @child&.mount
        def unmount = @child&.unmount
        def update(...) = @child&.update(...)

        def to_s = @child.to_s
        def traverse(&) = @child.traverse(&)
        def dom_node_name = @child.dom_node_name
        def dom_ids = @child.dom_ids
        def dom_id_tree = @child.dom_id_tree

        private

        def unwrap(descriptor)
          case Array(descriptor).compact.flatten
          in []
            ""
          in [one]
            one
          in [*many]
            many
          end
        end

        def descriptor_to_node_type(descriptor)
          case descriptor
          in Descriptors::Element[type: Class]
            VComponent
          in Descriptors::Element[type: :slot]
            VSlot
          in Descriptors::Element[type: :head]
            VHead
          in Descriptors::Element
            VElement
          in Descriptors::Comment
            VComment
          in Descriptors::Text
            VText
          in String | Numeric
            VText
          in Array
            VChildren
          in NilClass
            nil
          else
            raise "Unhandled descriptor: #{descriptor.inspect}"
          end
        end
      end

      class VDocument < Base
        H = Descriptors::H

        def initialize(...)
          super

          @head = {}
          @assets = Set.new
          @html = VComponent.new(init_html, parent: self)
        end

        def to_s
          puts "\e[3;32mRENDERING DOCUMENT\e[0m"
          "<!DOCTYPE html>\n#{@html.to_s}\n"
        end

        def add_head(vnode, children)
          @head[vnode] = children
          # @html.update(init_html)
        end

        def remove_head(vnode)
          puts "\e[3;31mRemoving from head #{vnode.inspect}"
          @head.delete(vnode)
          @html.update(init_html)
        end

        def add_asset(asset)
          return unless @assets.add?(asset)

          if asset.content_type == "text/css"
            patch do |patches|
              puts "Adding stylesheet #{asset.filename}"
              patches << Patches::AddStyleSheet[asset.filename]
              @html.update(init_html)
            end
          end
        end

        def dom_id_tree = @html.dom_id_tree.first
        def component_path = []

        def update(descriptor)
          @descriptor = descriptor

          patch { @html.update(init_html) }
        end

        def mount
          @task =
            Async do
              @html.mount&.wait
            rescue Unmount
              @html.unmount
            end
        end

        def unmount = Fiber.scheduler.raise(@task.fiber, Unmount)

        def update_children_order
          nil
        end

        private

        def init_html
          puts "\e[3;33m#{__method__}\e[0m"
          H[
            Components::HTML,
            H[
              Components::Head,
              user_tags: @head.values.flatten,
              key: "head",
              session_id: @parent.session_id,
              main_js:
                format(
                  "%s#%s",
                  File.join("/.mayu/runtime", @parent.environment.main_js),
                  @parent.session_id
                ),
              assets: @assets.to_a
            ],
            descriptor: @descriptor,
            key: "html"
          ]
        end
      end

      class VComponent < Base
        def initialize(...)
          super(...)

          if @descriptor.type.const_defined?(:COMPONENT_META)
            @descriptor.type.const_get(:COMPONENT_META) => { path: }

            Modules::System.get_assets_for_module(path).each { add_asset(_1) }
          end

          @instance = @descriptor.type.allocate
          @instance.instance_variable_set(:@props, @descriptor.props)
          @instance.send(:initialize)

          @children = VChildren.new(instance_render, parent: self)
        end

        def component_path = [*@parent.component_path, @descriptor.type]

        def mount
          @task =
            Async do |task|
              barrier = Async::Barrier.new
              queue = Async::Queue.new

              @instance.define_singleton_method(:rerender!) do
                queue.enqueue(:update!)
              end

              barrier.async { @instance.mount }

              barrier.async { @children.mount&.wait }

              loop do
                queue.wait
                @children.update(instance_render)
              end

              barrier.wait
            rescue Unmount
              @children.unmount
              @instance.unmount
            ensure
              barrier.stop
            end
        end

        def unmount
          puts "Called unmount"
          @task&.stop
        end

        def traverse(&)
          yield self
          @children.traverse(&)
        end

        def dom_ids = @children.dom_ids
        def dom_id_tree = @children.dom_id_tree
        def to_s = @children.to_s

        def update(new_descriptor)
          old_descriptor = @descriptor
          @descriptor = new_descriptor

          unless old_descriptor.props == @descriptor.props
            @instance.instance_variable_set(:@props, @descriptor.props)
          end

          @children.update(instance_render)
        end

        def get_slotted(name)
          Descriptors.group_by_slot(@descriptor.children)[name]
        end

        def marshal_dump
          [@id, @parent, @children, @descriptor, @instance]
        end

        def marshal_load(a)
          @id, @parent, @children, @descriptor, @instance = a
        end

        private

        def init_task
        end

        def instance_render
          @instance.render
        rescue => e
          component_meta = @instance.class::COMPONENT_META
          source_map = component_meta.source_map
          source_map.rewrite_exception(component_meta.path, e)

          puts e.full_message(highlight: true)

          interesting_lines =
            e
              .backtrace
              .grep(/\A#{Regexp.escape(component_meta.path)}:/)
              .map { _1.match(/:(\d+):/)[1].to_i }

          source_map
            .input
            .each_line
            .with_index(1) do |line, i|
              if interesting_lines.include?(i)
                puts format("\e[1;31m%3d: %s\e[0m", i, line.chomp)
              else
                puts format("%3d: %s", i, line.chomp)
              end
            end

          component_path.each_with_index do |part, index|
            if Class === part && part.const_defined?(:COMPONENT_META)
              meta = part::COMPONENT_META
              puts "#{"  " * index}\e[35m%\e[36m#{meta.name} \e[0;2m(#{meta.path})\e[0m"
            else
              puts "#{"  " * index}\e[35m%\e[36m#{part}\e[0m"
            end
          end

          patch do |patches|
            patches << Patches::RenderError[
              component_meta.path,
              e.class.name,
              e.message,
              e.backtrace,
              source_map.input
            ]
          end

          Descriptors::H[:p, "Error"]
        end
      end

      class VSlot < Base
        def initialize(...)
          super
          slotted_descriptors = get_slotted_descriptors
          puts "\e[3;35mInitializing vslot #{self.id}\e[0m #{slotted_descriptors.inspect}"
          @children = VChildren.new(slotted_descriptors, parent: self)
        end

        def dom_id_tree = @children.dom_id_tree
        def dom_ids = @children.dom_ids

        def update(descriptor)
          @descriptor = descriptor
          slotted_descriptors = get_slotted_descriptors
          puts "\e[3;35mUpdating vslot #{self.id}\e[0m #{slotted_descriptors.inspect}"
          @children.update(slotted_descriptors)
        end

        def get_slotted_descriptors
          get_slotted(@descriptor.props[:name])
        end

        def mount = @children.mount

        def unmount = @children.unmount

        def to_s = @children.to_s
      end

      class VChildren < Base
        STRING_SEPARATOR = Descriptors::Comment[""]

        attr_reader :children

        def initialize(...)
          super
          @children = []
          update(@descriptor)
        end

        def dom_ids = @children.map(&:dom_ids).flatten
        def dom_id_tree = @children.map(&:dom_id_tree)
        def to_s = @children.join

        def mount
          @task =
            Async do
              barrier = Async::Barrier.new

              @children.each { |child| barrier.async { child.mount&.wait } }

              barrier.wait
            end
        end

        def unmount
          @task&.stop
        end

        def traverse(&)
          yield self
          @children.traverse(&)
        end

        def update(descriptors)
          descriptors = normalize_descriptors(descriptors)

          return if descriptors.empty? && @children.empty?

          patch do
            grouped = @children.group_by { Descriptors.get_hash(_1.descriptor) }

            # if @children.any? { _1.descriptor == "Decrement" }
            #     binding.pry
            #   if descriptors.include?("Decrement")
            #     binding.pry
            #   end
            # end
            # binding.pry unless grouped.empty?

            new_children =
              descriptors
                .map do |descriptor|
                  if found = grouped[Descriptors.get_hash(descriptor)]&.shift
                    found.update(descriptor)
                    found
                  else
                    puts "\e[3;32mInitializing #{id}\e[0m #{descriptor.inspect}\e[0m"
                    VAny.new(descriptor, parent: self)
                  end
                end
                .compact

            @children = new_children

            @parent.update_children_order

            @children.each(&:after_initialize)

            unless grouped.values.flatten.empty?
              puts "\e[3;31mUnmounting #{id}\e[0m #{grouped.values.flatten.inspect}\e[0m"
              grouped.values.flatten.each(&:unmount)
            end
          end
        end

        private

        def normalize_descriptors(descriptors)
          Array(descriptors)
            .flatten
            .map { Descriptors.descriptor_or_string(_1) }
            .compact
            .then { insert_comments_between_strings(_1) }
        end

        def insert_comments_between_strings(descriptors)
          [nil, *descriptors].each_cons(2)
            .map do |prev, descriptor|
              case [prev, descriptor]
              in [String, String]
                [STRING_SEPARATOR, descriptor]
              else
                descriptor
              end
            end
            .flatten
        end
      end

      class VCallback < Base
        attr_reader :callback_id

        def initialize(...)
          super
          @callback_id = SecureRandom.alphanumeric(32)
        end

        def update(descriptor)
          @descriptor = descriptor
        end
      end

      class VElement < Base
        VOID_ELEMENTS = %i[
          area
          base
          br
          col
          embed
          hr
          img
          input
          link
          meta
          param
          source
          track
          wbr
        ]

        Listener =
          Data.define(:id, :callback) do
            def self.[](callback) = new(SecureRandom.alphanumeric(32), callback)

            def call(payload)
              method = callback.component.method(callback.method_name)

              case method.parameters
              in []
                method.call
              in [[:req, Symbol]]
                method.call(payload)
              in [[:keyrest, Symbol]]
                method.call(**payload)
              end
            end

            def callback_js = "Mayu.callback(event,'#{id}')"
          end

        def initialize(...)
          super

          @attributes = {}

          patch do |patches|
            patches << Patches::CreateElement[@id, tag_name]
            @attributes = update_attributes(@descriptor.props)
            @children = VChildren.new([], parent: self)
            @children.update(@descriptor.children)
          end
        end

        def dom_id_tree = IdNode[@id, dom_node_name, @children.dom_id_tree]
        def dom_node_name = tag_name.upcase

        def component_path = [*@parent.component_path, @descriptor.type]

        def mount = @children.mount

        def unmount
          patch do |patches|
            @children.unmount
            @attributes
              .values
              .select { _1.is_a?(Listener) }
              .each { @root.remove_listener(_1) }
            @attributes = {}
            patches << Patches::RemoveNode[@id]
          end
        end

        def update(new_descriptor)
          patch do |patches|
            @descriptor = new_descriptor
            @attributes = update_attributes(new_descriptor.props)
            @children.update(@descriptor.children)
          end
        end

        def traverse(&)
          yield self
          @children.traverse(&)
        end

        def tag_name =
          @descriptor.type.to_s.downcase.delete_prefix("__").tr("_", "-")

        def to_s
          identifier = ' data-mayu-id="%s"' % @id if INCLUDE_DEBUG_ID

          attributes =
            @attributes
              .map do |prop, value|
                next unless value

                next " #{prop}" if value == true

                if prop == :style && value.is_a?(Hash)
                  value = InlineStyle.stringify(value)
                end

                format(
                  ' %s="%s"',
                  CGI.escape_html(prop.to_s.tr("_", "-")),
                  if value.is_a?(Listener)
                    value.callback_js
                  else
                    CGI.escape_html(value.to_s)
                  end
                )
              end
              .join

          name = tag_name

          if VOID_ELEMENTS.include?(@descriptor.type)
            "<#{name}#{identifier}#{attributes}>"
          else
            "<#{name}#{identifier}#{attributes}>#{@children.to_s}</#{name}>"
          end
        end

        def parent_dom_id = @id

        def update_children_order
          return unless @children

          dom_ids = @children.dom_ids

          return if @dom_ids == dom_ids

          patch do |patches|
            patches << Patches::ReplaceChildren[@id, @dom_ids = dom_ids]
          end
        end

        private

        def update_attributes(props)
          patch do |patches|
            return(
              @attributes
                .keys
                .union(props.keys)
                .map do |prop|
                  old = @attributes[prop]
                  new = props[prop] || nil

                  if prop == :style
                    update_style(patches, prop, old, new)
                  elsif prop.start_with?("on")
                    update_callback(patches, prop, old, new)
                  else
                    update_attribute(patches, prop, old, new)
                  end
                end
                .compact
                .to_h
            )
          end
        end

        def update_attribute(patches, prop, old, new)
          unless new
            patches << Patches::RemoveAttribute[@id, new.to_s]
            return
          end

          [prop, old] if old.to_s == new.to_s

          if prop == :class
            patches << Patches::SetClassName[@id, new.to_s]
          else
            patches << Patches::SetAttribute[@id, prop, new.to_s]
          end

          [prop, new]
        end

        def update_style(patches, prop, old, new)
          unless new
            patches << Patches::RemoveAttribute[@id, :style]
            return
          end

          InlineStyle.diff(id, old || {}, new) { |patch| patches << patch }

          [prop, new]
        end

        def update_callback(patches, prop, old, new)
          if old
            return prop, old if old.callback.same?(new)

            @root.remove_listener(old)

            unless new
              patches << Patches::RemoveAttribute[@id, prop]
              return
            end
          end

          return unless new

          listener = @root.add_listener(Listener[new])
          patches << Patches::SetAttribute[@id, prop, listener.callback_js]

          [prop, listener]
        end
      end

      class VHead < Base
        def initialize(...)
          super
          # TODO:
          # add_to_document should be called here,
          # but somehow we get into an infinite loop if we do that.
        end

        def after_initialize
          add_to_document
        end

        def dom_id_tree = nil

        def update(new_descriptor)
          @descriptor = new_descriptor
          add_to_document
        end

        def to_s = ""

        def mount
          add_to_document
          nil
        end

        def unmount
          remove_from_document
          nil
        end

        private

        def add_to_document
          closest(VDocument).add_head(self, @descriptor.children)
        end

        def remove_from_document
          closest(VDocument).remove_head(self)
        end
      end

      class VText < Base
        ZERO_WIDTH_SPACE = "&ZeroWidthSpace;"

        def initialize(...)
          super
          patch do |patches|
            patches << Patches::CreateTextNode[@id, @descriptor.to_s]
          end
        end

        def update(new_descriptor)
          unless @descriptor.to_s == new_descriptor.to_s
            @descriptor = new_descriptor
            patch do |patches|
              patches << Patches::SetTextContent[@id, @descriptor.to_s]
            end
          end
        end

        def unmount
          patch { |patches| patches << Patches::RemoveNode[@id] }
        end

        def to_s
          if @descriptor.to_s.empty?
            ZERO_WIDTH_SPACE
          else
            CGI.escape_html(@descriptor.to_s)
          end
        end

        def dom_node_name = "#text"
      end

      class VComment < Base
        def initialize(...)
          super
          patch do |patches|
            patches << Patches::CreateComment[@id, escape_comment(@descriptor)]
          end
        end

        def update(descriptor)
          unless @descriptor.to_s == descriptor.to_s
            @descriptor = descriptor
            patch do |patches|
              patches << Patches::SetTextContent[
                @id,
                escape_comment(descriptor.to_s)
              ]
            end
          end
        end

        def unmount
          patch { |patches| patches << Patches::RemoveNode[@id] }
        end

        def to_s = "<!--#{escape_comment(@descriptor.content)}-->"

        def dom_node_name = "#comment"

        private

        def escape_comment(str) = str.to_s.gsub(/--/, "&#45;&#45;")
      end
    end
  end
end

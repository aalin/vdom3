# frozen_string_literal: true

# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "async"
require "async/barrier"
require "async/queue"
require "securerandom"
require "cgi"
require "pry"

require_relative "runtime/patches"
require_relative "runtime/inline_style"

require_relative "component"
require_relative "descriptors"

module VDOM
  INCLUDE_DEBUG_ID = false

  class Runtime
    class Unmount < Exception
    end

    module Components
      class HTML < Component::Base
        def render
          H[:html, H[:slot], @props[:descriptor], lang: @props[:lang]]
        end
      end

      class Head < Component::Base
        def render
          @props => { session_id:, main_js: }

          H[
            :__head,
            H[:meta, charset: "utf-8"],
            H[:slot, key: "user_tags"],
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

    class VNode
      def self.generate_id = SecureRandom.alphanumeric(10)

      attr_reader :id
      attr_reader :descriptor
      attr_reader :root
      attr_reader :parent

      def initialize(descriptor, parent: nil)
        @descriptor = descriptor
        @parent = parent
        @root = parent.root
        @id = VNode.generate_id
      end

      def patch(&)
        @root.patch(&)
      end

      def marshal_dump = [@id, @parent, @descriptor, @instance, @children]

      def closest(type) =
        if type === self
          self
        else
          @parent.closest(type)
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

      def init_child_vnode(descriptor)
        case descriptor
        in Descriptors::Element[type: Class]
          VComponent.new(descriptor, parent: self)
        in Descriptors::Element[type: :slot]
          VSlot.new(descriptor, parent: self)
        in Descriptors::Element[type: :head]
          VHead.new(descriptor, parent: self)
        in Descriptors::Element[type: :__head]
          VElement.new(descriptor.with(type: :head), parent: self)
        in Descriptors::Element
          VElement.new(descriptor, parent: self)
        in Descriptors::Comment
          VComment.new(descriptor, parent: self)
        in Descriptors::Text
          VText.new(descriptor, parent: self)
        in String | Numeric
          VText.new(descriptor.to_s, parent: self)
        in Array
          VChildren.new(descriptor, parent: self)
        in NilClass
          nil
        else
          raise "Unhandled descriptor: #{descriptor.inspect}"
        end
      end
    end

    class VDocument < VNode
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
        @html.update(init_html)
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
        H[
          Components::HTML,
          H[
            Components::Head,
            *@head.values.flatten,
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

    class VComponent < VNode
      def initialize(...)
        super(...)

        if @descriptor.type.const_defined?(:COMPONENT_META)
          @descriptor.type.const_get(:COMPONENT_META) => { path: }

          Modules::System.get_assets_for_module(path).each { add_asset(_1) }
        end

        @instance = @descriptor.type.allocate
        @instance.instance_variable_set(:@props, @descriptor.props)
        @instance.send(:initialize)
        @children = VChildren.new(@instance.render, parent: self)
      end

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
              @children.update(@instance.render)
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

        if old_descriptor.props != @descriptor.props ||
             old_descriptor.children != @descriptor.children
          @instance.instance_variable_set(:@props, @descriptor.props)
          @children.update(@instance.render)
        end
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
    end

    class VSlot < VNode
      def initialize(...)
        super
        @children =
          VChildren.new(get_slotted(@descriptor.props[:name]), parent: self)
      end

      def dom_id_tree = @children.dom_id_tree
      def dom_ids = @children.dom_ids

      def update(descriptor)
        @descriptor = descriptor
        @children.update(get_slotted(@descriptor.props[:name]))
      end

      def mount = @children.mount

      def unmount = @children.unmount

      def to_s = @children.to_s
    end

    class VChildren < VNode
      STRING_SEPARATOR = Descriptors::Comment[""]

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

          # binding.pry unless grouped.empty?

          new_children =
            descriptors
              .map do |descriptor|
                if found = grouped[Descriptors.get_hash(descriptor)]&.shift
                  found.update(descriptor)
                  found
                else
                  vnode = init_child_vnode(descriptor)
                  vnode
                end
              end
              .compact

          @children = new_children

          @parent.update_children_order

          grouped.values.flatten.each(&:unmount)
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

    class VCallback < VNode
      attr_reader :callback_id

      def initialize(...)
        super
        @callback_id = SecureRandom.alphanumeric(32)
      end

      def update(descriptor)
        @descriptor = descriptor
      end
    end

    class VStyles < VNode
      def initialize(...)
        super
      end

      def unmount
        patch { |patches| patches << Patches::RemoveAttribute[] }
      end
    end

    class VElement < VNode
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
          patches << Patches::CreateElement[@id, @descriptor.type]
          @attributes = update_attributes(@descriptor.props)
          @children = VChildren.new([], parent: self)
          @children.update(@descriptor.children)
        end
      end

      def dom_id_tree = IdNode[@id, dom_node_name, @children.dom_id_tree]
      def dom_node_name = @descriptor.type.to_s.upcase

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
        if new_descriptor.type === :__head
          new_descriptor = new_descriptor.with(type: :head)
        end

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

      def to_s
        identifier = ' data-mayu-id="%s"' % @id if INCLUDE_DEBUG_ID

        name = @descriptor.type.to_s.downcase.tr("_", "-")

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

    class VHead < VNode
      def initialize(...)
        super
        # TODO:
        # add_to_document should be called here,
        # but somehow we get into an infinite loop if we do that.
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

    class VText < VNode
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

    class VComment < VNode
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

    class PatchSet
      include Enumerable

      def initialize
        @patches = []
      end

      def each(&) = @patches.each(&)

      def push(patch) = @patches.push(patch)

      alias << push
    end

    attr_reader :session_id
    attr_reader :environment

    def initialize(environment:, session_id:)
      @environment = environment
      @session_id = session_id
      @patches = Async::Queue.new
      @callbacks = {}
      @document = VDocument.new(nil, parent: self)
      @running = false
    end

    def render(descriptor)
      @document.update(descriptor)
    end

    def root = self

    def to_html = @document.to_s

    def dom_id_tree = @document.dom_id_tree

    def clear_queue!
      puts "\e[33m#{@patches.dequeue.inspect}\e[0m" until @patches.empty?
    end

    def commit(patch_set)
      @patches.enqueue(patch_set.to_a) if @task
    end

    def run(&)
      raise "already running" if @task

      @task =
        Async do
          puts "mounting document"
          barrier = Async::Barrier.new

          barrier.async { @document.mount&.wait }

          barrier.async do
            puts "yielding"
            yield
          end

          barrier.wait
        ensure
          @document.unmount
          @task = nil
        end
    end

    def dequeue = @patches.dequeue

    def traverse(&) = @document.traverse(&)

    def add_listener(listener)
      puts "\e[32mRegistering listener #{listener.id}\e[0m"
      @callbacks.store(listener.id, listener)
    end

    def remove_listener(listener)
      puts "\e[33mRemoving listener #{listener.id}\e[0m"
      @callbacks.delete(listener.id)
    end

    def callback(id, payload)
      @callbacks.fetch(id).call(payload)
    end

    def patch
      if @patch_set
        yield @patch_set
        return
      end

      @patch_set = PatchSet.new

      begin
        yield @patch_set
      ensure
        patch_set = @patch_set
        @patch_set = nil
        commit(patch_set)
      end
    end

    def marshal_dump
      [@session_id, @document, @callbacks]
    end

    def marshal_load(a)
      @session_id, @document, @callbacks = a
      @task = Async::Task.current
      @patches = Async::Queue.new
    end
  end
end

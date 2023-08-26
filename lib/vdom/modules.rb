require "bundler/setup"
require "filewatcher"
require "pathname"

require_relative "component"

module VDOM
  module Modules
    module Registry
      HASH_LENGTH = 5

      def self.[](path)
        const_name = path_to_const_name(path)
        const_defined?(const_name) &&
          const_get(const_name)
      end

      def self.[]=(path, obj)
        const_name = path_to_const_name(path)
        const_set(const_name, obj)
        puts "\e[33mSetting #{self.name}::#{const_name} = #{obj.inspect}\e[0m"
        obj
      end

      def self.delete(path)
        const_name = path_to_const_name(path)
        const_defined?(const_name) &&
          remove_const(path_to_const_name(path))
      end

      def self.path_to_const_name(path)
        hash = Digest::SHA256.hexdigest(path.to_s)[0..HASH_LENGTH]
        name = path.to_s.gsub(/[^[a-zA-Z0-9]]/) { format("_%d_", _1.ord) }
        "Module_#{name}__#{hash}"
      end

      def self.const_name_to_path(const_name)
        const_name.gsub(/_(\d+)_/) do
          $~[1].to_i.chr("utf-8")
        end
      end
    end

    class Resolver
      class ResolveError < StandardError
      end

      attr_reader :root

      def initialize(root:, extensions: [])
        @root = root
        @extensions = extensions
        @resolved_paths = {}
      end

      def resolve(path, source_dir = "/")
        relative_to_root = File.absolute_path(path, source_dir)

        @resolved_paths.fetch(relative_to_root) do
          absolute_path = File.join(@root, relative_to_root)

          resolve_with_extensions(absolute_path) do |extension|
            return(
              @resolved_paths.store(
                relative_to_root,
                relative_to_root + extension
              )
            )
          end

          if File.directory?(absolute_path)
            basename = File.basename(absolute_path)

            resolve_with_extensions(
              File.join(absolute_path, basename)
            ) do |extension|
              return @resolved_paths.store(
                relative_to_root,
                File.join(relative_to_root, basename) + extension
              )
            end
          end

          raise ResolveError,
                "Could not resolve #{path} from #{source_dir} (app root: #{@root})"
        end
      end

      private

      def resolve_with_extensions(absolute_path, &block)
        @extensions.find do |extension|
          absolute_path_with_extension = absolute_path + extension

          if File.file?(absolute_path_with_extension)
            $stderr.puts "\e[1mFound #{absolute_path_with_extension}\e[0m"
            yield extension
          else
            $stderr.puts "\e[2mTried #{absolute_path_with_extension}\e[0m"
          end
        end
      end
    end

    class System
      CURRENT_KEY = :CurrentModulesSystem

      def self.run(root, &) =
        use(new(root), &)

      def self.use(system)
        previous = Fiber[CURRENT_KEY]
        Fiber[CURRENT_KEY] = system
        yield system
      ensure
        Fiber[CURRENT_KEY] = previous
      end

      def self.current
        Fiber[CURRENT_KEY] or raise "No active system"
      end

      def self.import(path, source_file = "/") =
        current.import(path, source_file)

      attr_reader :root

      def initialize(root)
        @root = Pathname.new(File.expand_path(root, Dir.pwd))

        @resolver = Resolver.new(
          root: @root,
          extensions: ["", ".haml"]
        )
      end

      def import(path, source_file = "/")
        resolved = @resolver.resolve(path, File.dirname(source_file))
        source = File.read(File.join(@root, resolved))

        component =
          Registry[resolved.to_s] ||= VDOM::Component::Loader.load_component(
            source,
            resolved
          )
        component::Export
      end

      def created(path)
      end

      def updated(path)
      end

      def deleted(path)
        Registry.delete(path)
      end

      def relative_from_root(absolute_path)
        Pathname.new(absolute_path).relative_path_from(@root)
      end

      def relative_to_absolute(relative_path)
        Pathname.new(File.join(@root), relative_path)
      end
    end

    class Watcher
      def self.run(system)
        Filewatcher.new([system.root]).watch do |changes|
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

if __FILE__ == $0
  VDOM::Modules::System.run("demo/") do |system|
    system.import("Demo.haml")

    VDOM::Modules::Watcher.run(system)
  end
end

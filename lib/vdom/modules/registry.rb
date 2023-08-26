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
  end
end

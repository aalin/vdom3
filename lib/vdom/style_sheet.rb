module VDOM
  module StyleSheet
    class Base
      def self.[](selector)
        self::CLASSES.fetch(selector) do
          Console::Logger.info("Could not find #{selector.inspect}")
        end
      end
    end
  end
end

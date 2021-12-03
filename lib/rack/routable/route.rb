# frozen_string_literal: true

module Rack
  module Routable
    class Route
      attr_reader :method, :path, :options, :action, :parsed_path

      def initialize(method, path, options, action, parsed_path)
        @method = method
        @path = path
        @options = options
        @action = action
        @parsed_path = parsed_path
      end

      def path_method_prefix
        return 'root' if path == '/'

        parts = []
        path.split('/').each do |part|
          parts << part.gsub(/\W+/, '_') unless part.start_with?(':') || part.empty?
        end
        parts.join('_')
      end

      def path_method_name
        "#{path_method_prefix}_path"
      end

      def url_method_name
        "#{path_method_prefix}_url"
      end

      def route_path(*args)
        vars = @path.scan(/(:\w+)/)

        if vars.length != args.length
          raise ArgumentError, "wrong number of arguments expected #{vars.length} got #{args.length}"
        end

        return @path if vars.length.zero?

        path = nil
        vars.each_with_index do |str, i|
          path = @path.sub(str[0], args[i].to_s)
        end
        path
      end

      def route_url(root, *args)
        "#{root}/#{route_path(*args)}"
      end

      def with_prefix(prefix)
        self.class.new(router, method, prefix + path, options, action, parsed_path)
      end
    end
  end
end

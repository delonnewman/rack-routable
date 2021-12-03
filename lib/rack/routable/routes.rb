# frozen_string_literal: true

module Rack
  module Routable
    # A routing table--collects routes, and matches them against a given Rack environment.
    #
    # @api private
    # @todo Add header matching
    class Routes
      include Enumerable

      def initialize
        @table = {}
        @routes = []
      end

      # Iterate over each route in the routes table passing it's information along
      # to the given block.
      #
      # @yield [Route]
      #
      # @return [Routes] this object
      def each_route(&block)
        routes.each(&block)
        self
      end
      alias each each_route

      # Add a route to the table.
      #
      # @param method [Symbol]
      # @param path [String]
      # @param action [#call]
      # @param headers [Hash]
      #
      # @return [Routes]
      def add!(method, path, action, options = EMPTY_HASH)
        self << Route.new(method, path, options, action, parse_path(path))
      end

      # Add a route to the table.
      #
      # @param Route [Route]
      #
      # @return [Routes]
      def <<(route)
        # TODO: Add Symbol#name for older versions of Ruby
        method = route.method.name.upcase
        @table[method] ||= []

        @table[method] << route
        @routes << route

        self
      end

      # Match a route in the table to the given Rack environment.
      #
      # @param env [Hash] a Rack environment
      #
      # @return [{ value: #call, params: Hash, options: Hash, env:? Hash }]
      def match(env, method = env['REQUEST_METHOD'])
        path   = env['PATH_INFO']
        path   = path.start_with?('/') ? path[1, path.size] : path
        parts  = path.split(/\/+/)

        if (routes = @table[method])
          routes.each do |route|
            if (params = match_path(parts, route.parsed_path))
              return { value: route.action, params: params, options: route.options }
            end
          end
        end

        false
      end

      private

      def parse_path(str)
        str   = str.start_with?('/') ? str[1, str.size] : str
        names = []

        route = str.split(/\/+/).each_with_index.map do |part, i|
          if part.start_with?(':')
            names[i] = part[1, part.size].to_sym
            NAME_PATTERN
          elsif part.end_with?('*')
            /^#{part[0, part.size - 1]}/i
          else
            part
          end
        end

        { names: names, path: route }
      end

      def path_start_with?(path, prefix)
        return true  if path == prefix
        return false if path.size < prefix.size

        res = false
        path.each_with_index do |part, i|
          res = true   if prefix[i] == part
          break        if prefix[i].nil?
          return false if prefix[i] != part
        end

        res
      end

      def match_path(path, route)
        return false if path.size != route[:path].size

        pattern = route[:path]
        names   = route[:names]
        params  = {}

        path.each_with_index do |part, i|
          return false unless pattern[i] === part
          if (name = names[i])
            params[name] = part
          end
        end

        params
      end

      NAME_PATTERN = /\A[\w\-]+\z/.freeze
      private_constant :NAME_PATTERN
    end
  end
end

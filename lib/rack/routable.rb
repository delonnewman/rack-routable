# frozen_string_literal: true

require 'cgi'
require 'rack'
require 'stringio'

module Rack
  # Provides a light-weight DSL for routing over Rack, and instances implement
  # the Rack application interface.
  #
  # @example
  #   class MyApp
  #     include Rack::Routable
  #
  #     # compose Rack middleware
  #     use Rack::Session
  #
  #     static '/' => 'public'
  #
  #     # block routes
  #     get '/hello' do
  #       'Hello'
  #     end
  #
  #     # 'callable' objects also work
  #     get '/hola', ->{ 'Hola' }
  #
  #     class Greeter
  #       def call
  #         'Miredita'
  #       end
  #     end
  #
  #     get '/miredita', Greeter
  #
  #     # dispatch based on headers
  #     get '/hello', content_type: :json do
  #       'Hello JSON'
  #     end
  #
  #     # nested routes
  #     on '/user/:id' do |user_id|
  #       @user = User.find(user_id)
  #
  #       get render: 'user/show'
  #       post do
  #         @user.update(params.slice(:username, :email))
  #       end
  #
  #       get '/settings', render: 'user/settings'
  #       post '/settings do
  #         @user.settings.update(params.slice(:settings))
  #       end
  #     end
  #
  #     # mount Rack apps
  #     mount '/admin', AdminApp
  #   end
  module Routable
    require_relative 'routable/route'
    require_relative 'routable/routes'

    # The default headers for responses
    DEFAULT_HEADERS = {
      'Content-Type' => 'text/html'
    }.freeze

    EMPTY_ARRAY = [].freeze
    EMPTY_HASH  = {}.freeze

    private_constant :EMPTY_HASH, :EMPTY_ARRAY

    def self.included(base)
      base.extend(ClassMethods)
      base.include(InstanceMethods)
    end

    # TODO: implement custom query parser

    module ClassMethods
      # A "macro" method to specify paths that should be used to serve static files.
      # They will be served from the "public" directory within the applications root_path.
      #
      # @param paths [Array<String>]
      def static(mapping)
        url  = mapping.first[0]
        root = mapping.first[1]
        use Rack::TryStatic, root: root, urls: [url], try: %w[.html index.html /index.html]
      end

      # A "macro" method to specify Rack middleware that should be used by this application.
      #
      # @param klass [Class] Rack middleware
      # @param args [Array] arguments for initializing the middleware
      def use(klass, *args)
        @middleware ||= []
        @middleware << [klass, args]
      end

      # Return an array of Rack middleware (used by this application) and their arguments.
      #
      # @return [Array<[Class, Array]>]
      def middleware
        @middleware || EMPTY_ARRAY
      end

      # A "macro" method for specifying the root_path of the application.
      # If called as a class method it will return the value that will be used
      # when instantiating.
      #
      # @param dir [String]
      # @return [String, nil]
      def root_path(dir = nil)
        @root_path = dir unless dir.nil?
        @root_path || '.'
      end

      # Rack interface
      #
      # @param env [Hash]
      # @returns Array<Integer, Hash, #each>
      def call(env)
        new(env).call
      end

      # Rack application
      def rack
        middleware.reduce(self) do |app, (klass, args)|
          klass.new(app, *args)
        end
      end

      # Valid methods for routes
      METHODS = %i[get post delete put head link unlink].to_set.freeze

      # Return the routing table for the class.
      #
      # @return [Routes]
      def routes
        @routes ||= Routes.new
      end

      # A "macro" method for defining a route for the application.
      #
      # @param method [:get, :post, :delete :put, :head, :link :unlink]
      def route(method, path, **options, &block)
        raise "Invalid method: #{method.inspect}" unless METHODS.include?(method)

        routes.add!(method, path, block, options)
      end

      METHODS.each do |method|
        define_method method do |path, **options, &block|
          route(method, path, **options, &block)
        end
      end

      def mount(prefix, app, **options)
        routes.mount!(prefix, app, options)
      end
    end

    module InstanceMethods
      attr_reader :env, :request, :params

      def initialize(env)
        @env      = env
        @request  = Request.new(env)
        @match    = self.class.routes.match(env, @request.request_method) || EMPTY_HASH
        @params   = @request.params.merge(@match[:params]) if @match && @match[:params]
        @response = Rack::Response.new
      end

      class Request < Rack::Request
        def request_method
          params.fetch('routable.http.method') do
            super()
          end.upcase
        end
      end

      protected

      # These methods must be used or overridden by the subclass

      attr_reader :match, :response

      def options
        match[:options] || EMPTY_HASH
      end

      def session
        request.session
      end

      def routes
        self.class.routes
      end

      def escape_html(*args)
        CGI.escapeHTML(*args)
      end
      alias h escape_html

      NOT_FOUND_TMPL = <<~HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <style>
               body {
                 font-family: sans-serif
               }

               main {
                 width: 80%;
                 margin-right: auto;
                 margin-left: auto;
               }

               table {
                 font-family: sans-serif;
                 border-spacing: 0;
                 border-collapse: collapse;
               }

               .routes table {
                 font-family: monospace;
               }

               .routes table, .routes table tr {
                 border: solid 1px #e0e0e0;
               }

               .routes table td, .routes table th {
                  padding: 5px 10px;
               }

               .environment {
                 margin-top: 20px;
                 max-width: 100vw;
               }

               .environment > h2 {
                  margin-bottom: 0;
               }

               .environment table td > pre {
                 max-height: 50px;
                 overflow: scroll;
               }

               .environment table th {
                 text-align: right;
                 padding-right: 10px;
               }
            </style>
          </head>
          <body>
            <main>
             %BODY%
            </main>
          </body>
        </html>
      HTML

      def not_found
        io = StringIO.new
        io.puts "<h1>Not Found</h1>"
        io.puts "#{request.request_method} - #{request.path}"

        unless ENV['RACK_ENV'] == 'production'
          io.puts "<div class=\"routes\"><h2>Valid Routes</h2>"
          io.puts "<table>"
          io.puts "<thead><tr><th>Method</th><th>Path</th><th>Router</th></thead>"
          io.puts "<tbody>"
          self.class.routes.each do |route|
            io.puts "<tr><td>#{h route.method}</td><td>#{h route.path}</td><td>#{h route.router.to_s}</td></tr>"
          end
          io.puts "</tbody></table></div>"

          io.puts "<div class=\"environment\"><h2>Environment</h2>"
          io.puts "<table><tbody>"
          env.each do |key, value|
            io.puts "<tr><th>#{h key}</th><td><pre>#{h value.pretty_inspect}</pre></td>"
          end
          io.puts "</tbody></table></div>"
        end

        [404, DEFAULT_HEADERS.dup, [NOT_FOUND_TMPL.sub('%BODY%', io.string)]]
      end

      def error(e)
        [500, DEFAULT_HEADERS.dup, StringIO.new('Server Error')]
      end

      def redirect_to(url)
        Rack::Response.new.tap do |r|
          r.redirect(url)
        end.finish
      end

      public

      # TODO: add error and not_found to the DSL
      def call
        return not_found if @match.empty?

        case @match[:tag]
        when :app
          @match[:value].call(@match[:env])
        when :action
          res = begin
                  instance_exec(params, @request, &@match[:value])
                rescue => e
                  if ENV.fetch('RACK_ENV') { :development }.to_sym == :production
                    env['rack.routable.error'] = e
                    return error(e)
                  else
                    raise e
                  end
                end

          if res.is_a?(Array) && res.size == 3 && res[0].is_a?(Integer)
            res
          elsif res.is_a?(Response)
            res.finish
          elsif res.is_a?(Hash) && res.key?(:status)
            [res[:status], res.fetch(:headers) { DEFAULT_HEADERS.dup }, res[:body]]
          elsif res.respond_to?(:each)
            [200, DEFAULT_HEADERS.dup, res]
          else
            [200, DEFAULT_HEADERS.dup, StringIO.new(res.to_s)]
          end
        end
      end
    end
  end
end

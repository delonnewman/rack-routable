require 'rack/routable'

RSpec.describe Rack::Routable do
  class Mounted
    include Rack::Routable

    post '/' do
      'posted to /'
    end
  end

  class TestApp
    include Rack::Routable

    mount '/test', ->(env) { env['PATH_INFO'] }
    mount '/mounted', Mounted

    get ?/ do
      'root dir'
    end

    get '/user/:id' do |params|
      "get user #{params[:id]}"
    end

    post '/user' do
      'create user'
    end
  end

  describe TestApp do
    it 'should respond to rack requests' do
      env = Rack::MockRequest.env_for('/user/1')
      expect(described_class.call(env)[2].string).to eq 'get user 1'
    end

    it 'should mount other rack apps' do
      { '/test' => '/', '/test/new' => '/new' }.each_pair do |prefixed, unprefixed|
        env = Rack::MockRequest.env_for(prefixed)
        expect(described_class.call(env)).to eq unprefixed
      end
    end

    it 'should pass post requests to mounted rack apps' do
      env = Rack::MockRequest.env_for('/mounted')
      env['REQUEST_METHOD'] = 'POST'
      expect(described_class.call(env)[2].string).to eq 'posted to /'
    end

    it 'should not give access to protected methods' do
      app = described_class.new(Rack::MockRequest.env_for('/'))
      %i[match response not_found error redirect_to options].each do |method|
        expect { app.send_public(method) }.to raise_error NoMethodError
      end
    end
  end
end

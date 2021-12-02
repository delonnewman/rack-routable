require 'rack/routable'

class TestApp
  include Rack::Routable

  get ?/ do
    'root dir'
  end

  get '/user/:id' do
    "get user #{params[:id]}"
  end

  post '/user' do
    'create user'
  end

  get '/simple', -> { 'Testing' }
end

RSpec.describe Rack::Routable do
  describe TestApp do
    it 'should respond to rack requests' do
      env = Rack::MockRequest.env_for('/user/1')
      expect(described_class.call(env)[2].string).to eq 'get user 1'
    end

    it 'should not give access to protected methods' do
      app = described_class.new(Rack::MockRequest.env_for('/'))
      %i[match response not_found error redirect_to options].each do |method|
        expect { app.send_public(method) }.to raise_error NoMethodError
      end
    end

    it 'should support procs for route actions' do
      env = Rack::MockRequest.env_for('/simple')
      expect(described_class.call(env)[2].string).to eq 'Testing'
    end
  end
end

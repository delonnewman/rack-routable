require 'rack/routable/routes'
require 'rack'

RSpec.describe Rack::Routable::Routes do
  describe '#match' do
    it 'should match simple paths' do
      $test = 1
      routes = described_class.new.add!(:get, '/testing', ->{ $test = 3 })
      match  = routes.match(Rack::MockRequest.env_for('/testing'))
      
      expect(match).not_to be false
      match[:value].call

      expect($test).to eq 3
    end

    it 'should match paths with variables' do
      $test = 1

      routes = described_class.new
                  .add!(:get, '/user/:id', ->{ $test = 4 })
                  .add!(:get, '/user/:id/settings', ->{ $test = 5 })
                  .add!(:get, '/user/:id/packages/:package_id', ->{ $test = 6 })

      match = routes.match(Rack::MockRequest.env_for('/user/1'))
      expect(match).not_to be false

      match[:value].call
      expect($test).to eq 4

      match = routes.match(Rack::MockRequest.env_for('/user/1/settings'))
      expect(match).not_to be false

      match[:value].call
      expect($test).to eq 5

      match = routes.match(Rack::MockRequest.env_for('/user/1/packages/abad564'))
      expect(match).not_to be false

      match[:value].call
      expect($test).to eq 6
    end
  end
end

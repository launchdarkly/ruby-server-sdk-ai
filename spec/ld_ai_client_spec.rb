# frozen_string_literal: true

require 'launchdarkly_server_sdk_ai'

RSpec.describe LaunchDarkly::AI::LDAIClient do
  let(:ld_client) { instance_double(LaunchDarkly::LDClient) }
  let(:context) { instance_double(LaunchDarkly::LDContext) }
  let(:client) { described_class.new(ld_client) }

  describe '#initialize' do
    it 'raises an error if LDClient is not provided' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, 'LDClient instance is required')
    end

    it 'raises an error if LDClient is not an instance of LaunchDarkly::LDClient' do
      expect { described_class.new('not a client') }.to raise_error(ArgumentError, 'LDClient instance is required')
    end

    it 'initializes with a valid LDClient instance' do
      expect(client.ld_client).to eq(ld_client)
      expect(client.logger).to eq(LaunchDarkly::AI.default_logger)
    end
  end

  describe '#config' do
    let(:config_key) { 'test-config' }
    let(:context) { instance_double(LaunchDarkly::LDContext) }
    let(:config_data) do
      {
        'model' => 'gpt-4',
        'temperature' => 0.7,
        'max_tokens' => 100,
        'messages' => [
          { 'role' => 'system', 'content' => 'You are a helpful assistant' }
        ],
        '_ldMeta' => { 'enabled' => true }
      }
    end

    before do
      allow(ld_client).to receive(:json_variation).with(config_key, context, {}).and_return(config_data)
    end

    it 'returns a tracker with the correct configuration' do
      tracker = client.config(config_key, context)
      expect(tracker).to be_a(LaunchDarkly::AI::LDAIConfigTracker)
      expect(tracker.ld_client).to eq(ld_client)
      expect(tracker.config_key).to eq(config_key)
      expect(tracker.context).to eq(context)
      expect(tracker.variation_key).to eq(config_key)
      expect(tracker.version).to eq(1)
    end

    it 'raises an error if the result is not a dictionary' do
      allow(ld_client).to receive(:json_variation).with(config_key, context, {}).and_return('not a dict')
      expect { client.config(config_key, context) }.to raise_error(ArgumentError, 'Result must be a dictionary')
    end

    it 'raises an error if _ldMeta is missing' do
      allow(ld_client).to receive(:json_variation).with(config_key, context, {}).and_return({})
      expect { client.config(config_key, context) }.to raise_error(ArgumentError, 'Result must contain _ldMeta')
    end

    it 'raises an error if _ldMeta.enabled is missing' do
      allow(ld_client).to receive(:json_variation).with(config_key, context, {}).and_return({ '_ldMeta' => {} })
      expect { client.config(config_key, context) }.to raise_error(ArgumentError, 'Result must contain _ldMeta.enabled')
    end

    it 'renders messages with variables' do
      config_data['messages'] = [
        { 'role' => 'system', 'content' => 'Hello {{name}}!' }
      ]
      config_data['name'] = 'World'
      
      tracker = client.config(config_key, context)
      expect(config_data['messages'][0]['content']).to eq('Hello World!')
    end

    it 'preserves messages without content' do
      config_data['messages'] = [
        { 'role' => 'system' }
      ]
      
      tracker = client.config(config_key, context)
      expect(config_data['messages'][0]).to eq({ 'role' => 'system' })
    end
  end
end

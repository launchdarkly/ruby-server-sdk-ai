# frozen_string_literal: true

require 'launchdarkly_server_sdk_ai'

RSpec.describe LaunchDarkly::AI::LDAIClient do
  let(:ld_client) { instance_double(LaunchDarkly::LDClient) }
  let(:context) { instance_double(LaunchDarkly::LDContext) }
  before {
    allow(ld_client).to receive(:is_a?).with(LaunchDarkly::LDClient).and_return(true)
    allow(context).to receive(:is_a?).with(LaunchDarkly::LDContext).and_return(true)
  }

  describe '#initialize' do
    it '1.2.1: initializes with a valid LDClient instance' do
      ai_client = described_class.new(ld_client)
      expect { ai_client }.not_to raise_error
      expect(ai_client).to be_a(LaunchDarkly::AI::LDAIClient)
      expect(ai_client.ld_client).to eq(ld_client)
      expect(ai_client.logger).to be_a(Logger)
    end

    it '1.2.2: raises an error if LDClient is not provided' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, 'LDClient instance is required')
    end

    it '1.2.2: raises an error if LDClient is not an instance of LaunchDarkly::LDClient' do
      expect { described_class.new('not a client') }.to raise_error(ArgumentError, 'LDClient instance is required')
    end
  end

  describe '#config' do
    let(:key) { 'key-123' }
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

    it 'The LDAIClient MUST provide a method for retrieving a model config' do
      ai_client = described_class.new(ld_client)
      ai_config = LaunchDarkly::AI::AIConfig.new
      allow(ld_client).to receive(:variation).with(key, context, ai_config.to_h).and_return(config_data)

      
      config = ai_client.config(key, context, ai_config)
      expect(config).to be_a(LaunchDarkly::AI::AIConfig)
      expect(config.enabled).to be false
    end

    # it 'returns a tracker with the correct configuration' do
    #   ai_client = described_class.new(ld_client)
    #   tracker = ai_client.config(config_key, context)
    #   expect(tracker).to be_a(LaunchDarkly::AI::LDAIConfigTracker)
    #   expect(tracker.ld_client).to eq(ld_client)
    #   expect(tracker.config_key).to eq(config_key)
    #   expect(tracker.context).to eq(context)
    #   expect(tracker.variation_key).to eq(config_key)
    #   expect(tracker.version).to eq(1)
    # end

    # it 'raises an error if the result is not a dictionary' do
    #   ai_client = described_class.new(ld_client)
    #   allow(ld_client).to receive(:json_variation).with(config_key, context, {}).and_return('not a dict')
    #   expect { ai_client.config(config_key, context) }.to raise_error(ArgumentError, 'Result must be a dictionary')
    # end

    # it 'raises an error if _ldMeta is missing' do
    #   ai_client = described_class.new(ld_client)
    #   allow(ld_client).to receive(:json_variation).with(config_key, context, {}).and_return({})
    #   expect { ai_client.config(config_key, context) }.to raise_error(ArgumentError, 'Result must contain _ldMeta')
    # end

    # it 'raises an error if _ldMeta.enabled is missing' do
    #   ai_client = described_class.new(ld_client)
    #   allow(ld_client).to receive(:json_variation).with(config_key, context, {}).and_return({ '_ldMeta' => {} })
    #   expect { ai_client.config(config_key, context) }.to raise_error(ArgumentError, 'Result must contain _ldMeta.enabled')
    # end

    # it 'renders messages with variables' do
    #   ai_client = described_class.new(ld_client)
    #   config_data['messages'] = [
    #     { 'role' => 'system', 'content' => 'Hello {{name}}!' }
    #   ]
    #   config_data['name'] = 'World'
      
    #   tracker = ai_client.config(config_key, context)
    #   expect(config_data['messages'][0]['content']).to eq('Hello World!')
    # end

    # it 'preserves messages without content' do
    #   ai_client = described_class.new(ld_client)
    #   config_data['messages'] = [
    #     { 'role' => 'system' }
    #   ]
      
    #   tracker = ai_client.config(config_key, context)
    #   expect(config_data['messages'][0]).to eq({ 'role' => 'system' })
    # end
  end
end

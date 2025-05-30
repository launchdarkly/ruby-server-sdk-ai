# frozen_string_literal: true

require 'ldclient-rb'
require 'ldclient-ai'

RSpec.describe LaunchDarkly::AI::LDAIClient do
  let(:td) { LaunchDarkly::Integrations::TestData.data_source() }
  let(:config) { LaunchDarkly::Config.new({data_source: td}) }
  let(:ld_client) { LaunchDarkly::LDClient.new('key', config) }
  let(:ai_client) { described_class.new(ld_client) }
  let(:default_config) { LaunchDarkly::AI::AIConfig.default }

  before do
    allow(ld_client).to receive(:is_a?).with(LaunchDarkly::LDClient).and_return(true)
  end

  describe '#initialize' do
    it 'initializes with a valid LDClient instance' do
      ai_client = described_class.new(ld_client)
      expect(ai_client).to be_a(LaunchDarkly::AI::LDAIClient)
      expect(ai_client.ld_client).to eq(ld_client)
    end

    it 'raises an error if LDClient is not provided' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, 'LDClient instance is required')
    end

    it 'raises an error if LDClient is not an instance of LaunchDarkly::LDClient' do
      expect { described_class.new('not a client') }.to raise_error(ArgumentError, 'LDClient instance is required')
    end
  end

  describe '#config' do
    let(:config_data) do
      {
        'enabled' => true,
        'model' => 'gpt-4',
        'temperature' => 0.7,
        'max_tokens' => 100,
        'messages' => [
          { 'role' => 'system', 'content' => 'You are a helpful assistant' }
        ]
      }
    end

    it 'returns an AIConfig instance with the correct data' do
      context = LaunchDarkly::LDContext.create('user-key')
      config = ai_client.config(key, context)
      expect(config).to be_a(LaunchDarkly::AI::AIConfig)
      expect(config.enabled).to be true
      expect(config.variables['model']).to eq('gpt-4')
      expect(config.variables['temperature']).to eq(0.7)
      expect(config.variables['max_tokens']).to eq(100)
      expect(config.messages[0]['role']).to eq('system')
      expect(config.messages[0]['content']).to eq('You are a helpful assistant')
    end

    it 'renders message content with variables' do
      config_data['messages'] = [
        { 'role' => 'system', 'content' => 'Hello {{name}}!' }
      ]
      config_data['name'] = 'World'
      context = LaunchDarkly::LDContext.create('user-key')

      config = ai_client.config(key, context)
      expect(config.messages[0]['content']).to eq('Hello World!')
    end

    it 'preserves messages without content' do
      config_data['messages'] = [
        { 'role' => 'system' }
      ]

      context = LaunchDarkly::LDContext.create('user-key')
      config = ai_client.config(key, context)
      expect(config.messages[0]).to eq({ 'role' => 'system' })
    end

    it 'includes context in variables' do
      context = LaunchDarkly::LDContext.create('user-key')

      config = ai_client.config(key, context)
      expect(config.variables['ldctx']).to eq({ key: 'test-user' })
    end

    it 'handles custom variables' do
      custom_vars = { 'custom' => 'value' }
      context = LaunchDarkly::LDContext.create('user-key')

      config = ai_client.config(key, context, default_config, variables: custom_vars)
      expect(config.variables['custom']).to eq('value')
    end

    it 'returns default config when variation returns nil' do
      context = LaunchDarkly::LDContext.create('user-key')

      config = ai_client.config(key, context)
      expect(config).to be_a(LaunchDarkly::AI::AIConfig)
      expect(config.enabled).to be false
      expect(config.messages).to be_nil
      expect(config.variables).to be_nil
    end

    it 'creates a tracker with the correct configuration' do
      context = LaunchDarkly::LDContext.create('user-key')

      config = ai_client.config(key, context)
      expect(config.tracker).to be_a(LaunchDarkly::AI::LDAIConfigTracker)
      expect(config.tracker.ld_client).to eq(ld_client)
      expect(config.tracker.config_key).to eq(key)
      expect(config.tracker.context).to eq(context)
      expect(config.tracker.variation_key).to eq(key)
      expect(config.tracker.version).to eq(1)
    end
  end
end

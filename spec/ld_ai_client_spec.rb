# frozen_string_literal: true

require 'ldclient-rb'
require 'ldclient-ai'

RSpec.describe LaunchDarkly::AI::LDAIClient do
  let(:td) do
    data_source = LaunchDarkly::Integrations::TestData.data_source
    data_source.update(data_source.flag('model-config')
      .variations(
            {
                'model': {'name': 'fakeModel', 'parameters': {'temperature': 0.5, 'maxTokens': 4096}, 'custom': {'extra-attribute': 'value'}},
                'provider': {'name': 'fakeProvider'},
                'messages': [{'role': 'system', 'content': 'Hello, {{name}}!'}],
                '_ldMeta': {'enabled': true, 'variationKey': 'abcd', 'version': 1},
            },
            "green",
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('multiple-messages')
      .variations(
            {
                'model': {'name': 'fakeModel', 'parameters': {'temperature': 0.7, 'maxTokens': 8192}},
                'messages': [
                    {'role': 'system', 'content': 'Hello, {{name}}!'},
                    {'role': 'user', 'content': 'The day is, {{day}}!'},
                ],
                '_ldMeta': {'enabled': true, 'variationKey': 'abcd', 'version': 1},
            },
            "green",
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('ctx-interpolation')
      .variations(
            {
                'model': {'name': 'fakeModel', 'parameters': {'extra-attribute': 'I can be anything I set my mind/type to'}},
                'messages': [{'role': 'system', 'content': 'Hello, {{ldctx.name}}! Is your last name {{ldctx.last}}?'}],
                '_ldMeta': {'enabled': true, 'variationKey': 'abcd', 'version': 1},
            }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('multi-ctx-interpolation')
        .variations(
            {
                'model': {'name': 'fakeModel', 'parameters': {'extra-attribute': 'I can be anything I set my mind/type to'}},
                'messages': [{'role': 'system', 'content': 'Hello, {{ldctx.user.name}}! Do you work for {{ldctx.org.shortname}}?'}],
                '_ldMeta': {'enabled': true, 'variationKey': 'abcd', 'version': 1},
            }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('off-config')
        .variations(
            {
                'model': {'name': 'fakeModel', 'parameters': {'temperature': 0.1}},
                'messages': [{'role': 'system', 'content': 'Hello, {{name}}!'}],
                '_ldMeta': {'enabled': false, 'variationKey': 'abcd', 'version': 1},
            }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('initial-config-disabled')
        .variations(
            {
                '_ldMeta': {'enabled': false},
            },
            {
                '_ldMeta': {'enabled': true},
            }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('initial-config-enabled')
        .variations(
            {
                '_ldMeta': {'enabled': false},
            },
            {
                '_ldMeta': {'enabled': true},
            }
        )
        .variation_for_all(1))

    data_source
  end

  let(:sdk_key) { 'sdk-key' }
  let(:config) { LaunchDarkly::Config.new(data_source: td) }
  let(:ld_client) { LaunchDarkly::LDClient.new(sdk_key, config) }
  let(:context) { LaunchDarkly::LDContext.create({ key: 'test-user' }) }
  let(:key) { 'model-config' }
  let(:default_config) { LaunchDarkly::AI::AIConfig.default }

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
    it 'returns an AIConfig instance with the correct data' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config(key, context)
      expect(config).to be_a(LaunchDarkly::AI::AIConfig)
      expect(config.enabled).to be false
      expect(config.variables['model']).to eq('gpt-4')
      expect(config.variables['temperature']).to eq(0.7)
      expect(config.variables['max_tokens']).to eq(100)
      expect(config.messages[0]['role']).to eq('system')
      expect(config.messages[0]['content']).to eq('You are a helpful assistant')
    end

    it 'renders message content with variables' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config('model-config-message-content', context)
      expect(config.messages[0]['content']).to eq('Hello World!')
    end

    it 'preserves messages without content' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config('model-config-no-content', context)
      expect(config.messages[0]).to eq({ 'role' => 'system' })
    end

    it 'includes context in variables' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config(key, context)
      expect(config.variables['ldctx']).to eq({ key: 'test-user' })
    end

    it 'handles custom variables' do
      custom_vars = { 'custom' => 'value' }
      ai_client = described_class.new(ld_client)
      config = ai_client.config(key, context, default_config, variables: custom_vars)
      expect(config.variables['custom']).to eq('value')
    end

    it 'returns default config when flag is off' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config('model-config-default', context)
      expect(config).to be_a(LaunchDarkly::AI::AIConfig)
      expect(config.enabled).to be false
      expect(config.messages).to be_nil
      expect(config.variables).to be_nil
    end

    it 'creates a tracker with the correct configuration' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config(key, context)
      expect(config.tracker).to be_a(LaunchDarkly::AI::LDAIConfigTracker)
      expect(config.tracker.ld_client).to eq(ld_client)
      expect(config.tracker.config_key).to eq(key)
      expect(config.tracker.context).to eq(context)
      expect(config.tracker.variation_key).to eq(key)
      expect(config.tracker.version).to eq(1)
    end

    it 'handles fallthrough variation' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config('model-config-fallthrough', context)
      expect(config.enabled).to be false
      expect(config.variables['model']).to eq('gpt-3.5-turbo')
    end

    it 'handles multiple variations' do
      ai_client = described_class.new(ld_client)
      config = ai_client.config('model-config-multiple', context)
      expect(config.enabled).to be true
      expect(config.variables['model']).to eq('claude-2')
    end
  end
end

# frozen_string_literal: true

require 'ldclient-rb'
require 'ldclient-ai'

RSpec.describe LaunchDarkly::AI::LDAIClient do
  let(:td) do
    data_source = LaunchDarkly::Integrations::TestData.data_source
    data_source.update(data_source.flag('model-config')
      .variations(
        {
          model: { name: 'fakeModel', parameters: { temperature: 0.5, maxTokens: 4096 },
                   custom: { 'extra-attribute': 'value' } },
          provider: { name: 'fakeProvider' },
          messages: [{ role: 'system', content: 'Hello, {{name}}!' }],
          _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 }
        },
        :green
      )
        .variation_for_all(0))

    data_source.update(data_source.flag('multiple-messages')
      .variations(
        {
          model: { name: 'fakeModel', parameters: { temperature: 0.7, maxTokens: 8192 } },
          messages: [
            { role: 'system', content: 'Hello, {{name}}!' },
            { role: 'user', content: 'The day is, {{day}}!' }
          ],
          _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 }
        },
        :green
      )
        .variation_for_all(0))

    data_source.update(data_source.flag('ctx-interpolation')
      .variations(
        {
          model: { name: 'fakeModel',
                   parameters: { 'extra-attribute': 'I can be anything I set my mind/type to' } },
          messages: [{ role: 'system', content: 'Hello, {{ldctx.name}}! Is your last name {{ldctx.last}}?' }],
          _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 }
        }
      )
        .variation_for_all(0))

    data_source.update(data_source.flag('multi-ctx-interpolation')
        .variations(
          {
            model: { name: 'fakeModel',
                     parameters: { 'extra-attribute': 'I can be anything I set my mind/type to' } },
            messages: [{ role: 'system',
                         content: 'Hello, {{ldctx.user.name}}! Do you work for {{ldctx.org.shortname}}?' }],
            _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 }
          }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('off-config')
        .variations(
          {
            model: { name: 'fakeModel', parameters: { temperature: 0.1 } },
            messages: [{ role: 'system', content: 'Hello, {{name}}!' }],
            _ldMeta: { enabled: false, variationKey: 'abcd', version: 1 }
          }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('initial-config-disabled')
        .variations(
          {
            _ldMeta: { enabled: false }
          },
          {
            _ldMeta: { enabled: true }
          }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('initial-config-enabled')
        .variations(
          {
            _ldMeta: { enabled: false }
          },
          {
            _ldMeta: { enabled: true }
          }
        )
        .variation_for_all(1))

    data_source
  end

  let(:ld_client) do
    config = LaunchDarkly::Config.new(data_source: td, send_events: false)
    LaunchDarkly::LDClient.new('sdk-key', config)
  end
  let(:ai_client) { LaunchDarkly::AI::LDAIClient.new(ld_client) }
  let(:context) { LaunchDarkly::LDContext.create({ key: 'test-user' }) }
  let(:key) { 'model-config' }
  let(:default_config) { LaunchDarkly::AI::AIConfig.default }

  describe '#initialize' do
    it 'initializes with a valid LDClient instance' do
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
    it 'delegates to properties' do
      model = LaunchDarkly::AI::ModelConfig.new(name: 'fakeModel', parameters: { 'extra-attribute': 'value' })
      expect(model.name).to eq('fakeModel')
      expect(model.get_parameter(:'extra-attribute')).to eq('value')
      expect(model.get_parameter('non-existent')).to be_nil
      expect(model.get_parameter('name')).to eq('fakeModel')
    end

    it 'handles custom attributes' do
      model = LaunchDarkly::AI::ModelConfig.new(name: 'fakeModel', custom: { 'extra-attribute': 'value' })
      expect(model.name).to eq('fakeModel')
      expect(model.get_custom(:'extra-attribute')).to eq('value')
      expect(model.get_custom('non-existent')).to be_nil
      expect(model.get_custom('name')).to be_nil
    end

    it 'uses default config on invalid flag' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
      model = LaunchDarkly::AI::ModelConfig.new(name: 'fakeModel',
                                                parameters: {
                                                  temperature: 0.5, maxTokens: 4096
                                                })
      messages = [LaunchDarkly::AI::LDMessage.new('system', 'Hello, {{name}}!')]
      default_config = LaunchDarkly::AI::AIConfig.new(
        enabled: true,
        model: model,
        messages: messages
      )
      variables = { 'name' => 'World' }

      config = ai_client.config('missing-flag', context, default_config, variables)
      expect(config.messages).not_to be_nil
      expect(config.messages.length).to be > 0
      expect(config.messages[0][:content]).to eq('Hello, World!')
      expect(config.enabled).to be true

      expect(config.model).not_to be_nil
      expect(config.model.name).to eq('fakeModel')
      expect(config.model.get_parameter(:temperature)).to eq(0.5)
      expect(config.model.get_parameter(:maxTokens)).to eq(4096)
    end

    it 'interpolates variables in model config messages' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: true,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fakeModel'),
        messages: [LaunchDarkly::AI::LDMessage.new('system', 'Hello, {{name}}!')]
      )
      variables = { 'name' => 'World' }

      config = ai_client.config('model-config', context, default_value, variables)
      expect(config.messages).not_to be_nil
      expect(config.messages.length).to be > 0
      expect(config.messages[0][:content]).to eq('Hello, World!')
      expect(config.enabled).to be true

      expect(config.model).not_to be_nil
      expect(config.model.name).to eq('fakeModel')
      expect(config.model.get_parameter(:temperature)).to eq(0.5)
      expect(config.model.get_parameter(:maxTokens)).to eq(4096)
    end

    it 'returns config with messages interpolated as empty when no variables are provided' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: true,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fakeModel'),
        messages: []
      )

      config = ai_client.config('model-config', context, default_value, {})

      expect(config.messages).not_to be_nil
      expect(config.messages.length).to be > 0
      expect(config.messages[0][:content]).to eq('Hello, !')
      expect(config.enabled).to be true

      expect(config.model).not_to be_nil
      expect(config.model.name).to eq('fakeModel')
      expect(config.model.get_parameter(:temperature)).to eq(0.5)
      expect(config.model.get_parameter(:maxTokens)).to eq(4096)
    end

    it 'handles provider config correctly' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user', name: 'Sandy' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: true,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fake-model'),
        messages: []
      )
      variables = { 'name' => 'World' }

      config = ai_client.config('model-config', context, default_value, variables)

      expect(config.provider).not_to be_nil
      expect(config.provider.name).to eq('fakeProvider')
    end

    it 'interpolates context variables in messages using ldctx' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user', name: 'Sandy', last: 'Beaches' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: true,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fake-model'),
        messages: []
      )
      variables = { 'name' => 'World' }

      config = ai_client.config('ctx-interpolation', context, default_value, variables)

      expect(config.messages).not_to be_nil
      expect(config.messages.length).to be > 0
      expect(config.messages[0][:content]).to eq('Hello, Sandy! Is your last name Beaches?')
      expect(config.enabled).to be true

      expect(config.model).not_to be_nil
      expect(config.model.name).to eq('fakeModel')
      expect(config.model.get_parameter(:temperature)).to be_nil
      expect(config.model.get_parameter(:maxTokens)).to be_nil
      expect(config.model.get_parameter(:'extra-attribute')).to eq('I can be anything I set my mind/type to')
    end

    it 'interpolates variables from multiple contexts in messages using ldctx' do
      user_context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user', name: 'Sandy' })
      org_context = LaunchDarkly::LDContext.create({ key: 'org-key', kind: 'org', name: 'LaunchDarkly',
                                                     shortname: 'LD' })
      context = LaunchDarkly::LDContext.create_multi([user_context, org_context])
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: true,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fake-model'),
        messages: []
      )
      variables = { 'name' => 'World' }

      config = ai_client.config('multi-ctx-interpolation', context, default_value, variables)

      expect(config.messages).not_to be_nil
      expect(config.messages.length).to be > 0
      expect(config.messages[0][:content]).to eq('Hello, Sandy! Do you work for LD?')
      expect(config.enabled).to be true

      expect(config.model).not_to be_nil
      expect(config.model.name).to eq('fakeModel')
      expect(config.model.get_parameter(:temperature)).to be_nil
      expect(config.model.get_parameter(:maxTokens)).to be_nil
      expect(config.model.get_parameter(:'extra-attribute')).to eq('I can be anything I set my mind/type to')
    end

    it 'handles multiple messages and variable interpolation' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: true,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fake-model'),
        messages: []
      )
      variables = { 'name' => 'World', 'day' => 'Monday' }

      config = ai_client.config('multiple-messages', context, default_value, variables)

      expect(config.messages).not_to be_nil
      expect(config.messages.length).to be > 0
      expect(config.messages[0][:content]).to eq('Hello, World!')
      expect(config.messages[1][:content]).to eq('The day is, Monday!')
      expect(config.enabled).to be true

      expect(config.model).not_to be_nil
      expect(config.model.name).to eq('fakeModel')
      expect(config.model.get_parameter(:temperature)).to eq(0.7)
      expect(config.model.get_parameter(:maxTokens)).to eq(8192)
    end

    it 'returns disabled config when flag is off' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: false,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fake-model'),
        messages: []
      )

      config = ai_client.config('off-config', context, default_value, {})

      expect(config.model).not_to be_nil
      expect(config.enabled).to be false
      expect(config.model.name).to eq('fakeModel')
      expect(config.model.get_parameter(:temperature)).to eq(0.1)
      expect(config.model.get_parameter(:maxTokens)).to be_nil
    end

    it 'returns disabled config with nil model/messages/provider when initial config is disabled' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: false,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fake-model'),
        messages: []
      )

      config = ai_client.config('initial-config-disabled', context, default_value, {})

      expect(config.enabled).to be false
      expect(config.model).to be_nil
      expect(config.messages).to be_nil
      expect(config.provider).to be_nil
    end

    it 'returns enabled config with nil model/messages/provider when initial config is enabled' do
      context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
      default_value = LaunchDarkly::AI::AIConfig.new(
        enabled: false,
        model: LaunchDarkly::AI::ModelConfig.new(name: 'fake-model'),
        messages: []
      )

      config = ai_client.config('initial-config-enabled', context, default_value, {})

      expect(config.enabled).to be true
      expect(config.model).to be_nil
      expect(config.messages).to be_nil
      expect(config.provider).to be_nil
    end
  end
end

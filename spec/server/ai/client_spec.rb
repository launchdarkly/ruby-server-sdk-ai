# frozen_string_literal: true

require 'launchdarkly-server-sdk'
require 'launchdarkly-server-sdk-ai'

RSpec.describe LaunchDarkly::Server::AI do
  let(:td) do
    data_source = LaunchDarkly::Integrations::TestData.data_source
    data_source.update(data_source.flag('model-config')
      .variations(
        {
          model: { name: 'fakeModel', parameters: { temperature: 0.5, maxTokens: 4096 },
                   custom: { 'extra-attribute': 'value' } },
          provider: { name: 'fakeProvider' },
          messages: [{ role: 'system', content: 'Hello, {{name}}!' }],
          _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 },
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
            { role: 'user', content: 'The day is, {{day}}!' },
          ],
          _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 },
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
          _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 },
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
            _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 },
          }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('off-config')
        .variations(
          {
            model: { name: 'fakeModel', parameters: { temperature: 0.1 } },
            messages: [{ role: 'system', content: 'Hello, {{name}}!' }],
            _ldMeta: { enabled: false, variationKey: 'abcd', version: 1 },
          }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('initial-config-disabled')
        .variations(
          {
            _ldMeta: { enabled: false },
          },
          {
            _ldMeta: { enabled: true },
          }
        )
        .variation_for_all(0))

    data_source.update(data_source.flag('initial-config-enabled')
        .variations(
          {
            _ldMeta: { enabled: false },
          },
          {
            _ldMeta: { enabled: true },
          }
        )
        .variation_for_all(1))

    data_source
  end

  let(:ld_client) do
    config = LaunchDarkly::Config.new(data_source: td, send_events: false)
    LaunchDarkly::LDClient.new('sdk-key', config)
  end
  let(:ai_client) { LaunchDarkly::Server::AI::Client.new(ld_client) }

  describe LaunchDarkly::Server::AI::ModelConfig do
    it 'delegates to properties' do
      model = described_class.new(name: 'fakeModel', parameters: { 'extra-attribute': 'value' })
      expect(model.name).to eq('fakeModel')
      expect(model.parameter(:'extra-attribute')).to eq('value')
      expect(model.parameter('non-existent')).to be_nil
      expect(model.parameter('name')).to eq('fakeModel')
    end

    it 'handles custom attributes' do
      model = described_class.new(name: 'fakeModel', custom: { 'extra-attribute': 'value' })
      expect(model.name).to eq('fakeModel')
      expect(model.custom(:'extra-attribute')).to eq('value')
      expect(model.custom('non-existent')).to be_nil
      expect(model.custom('name')).to be_nil
    end
  end

  describe LaunchDarkly::Server::AI::Client do
    describe '#initialize' do
      it 'initializes with a valid LDClient instance' do
        expect(ai_client).to be_a(described_class)
        expect(ai_client.ld_client).to eq(ld_client)
      end

      it 'raises an error if LDClient is not provided' do
        expect { described_class.new(nil) }.to raise_error(ArgumentError, 'LDClient instance is required')
      end

      it 'raises an error if LDClient is not an instance of LaunchDarkly::LDClient' do
        expect { described_class.new('not a client') }.to raise_error(ArgumentError, 'LDClient instance is required')
      end

      it 'tracks sdk-info on construction' do
        expect(ld_client).to receive(:track).with(
          '$ld:ai:sdk:info',
          an_object_satisfying { |ctx| ctx.kind == 'ld_ai' && ctx.key == 'ld-internal-tracking' && ctx.get_value(:anonymous) == true },
          {
            aiSdkName: LaunchDarkly::Server::AI::SDK_NAME,
            aiSdkVersion: LaunchDarkly::Server::AI::VERSION,
            aiSdkLanguage: LaunchDarkly::Server::AI::SDK_LANGUAGE,
          },
          1
        )
        described_class.new(ld_client)
      end
    end

    describe '#completion_config' do
      it 'uses default config on invalid flag' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        model = LaunchDarkly::Server::AI::ModelConfig.new(name: 'fakeModel',
                                                  parameters: {
                                                    temperature: 0.5, maxTokens: 4096
                                                  })
        messages = [LaunchDarkly::Server::AI::Message.new('system', 'Hello, {{name}}!')]
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: model,
          messages: messages
        )
        variables = { 'name' => 'World' }

        config = ai_client.completion_config(key: 'missing-flag', context:, default:, variables:)
        expect(config.messages).not_to be_nil
        expect(config.messages.length).to be > 0
        expect(config.messages[0].content).to eq('Hello, World!')
        expect(config.enabled).to be true

        expect(config.model).not_to be_nil
        expect(config.model.name).to eq('fakeModel')
        expect(config.model.parameter(:temperature)).to eq(0.5)
        expect(config.model.parameter(:maxTokens)).to eq(4096)
      end

      it 'interpolates variables in model config messages' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fakeModel'),
          messages: [LaunchDarkly::Server::AI::Message.new('system', 'Hello, {{name}}!')]
        )
        variables = { 'name' => 'World' }

        config = ai_client.completion_config(key: 'model-config', context:, default:, variables:)
        expect(config.messages).not_to be_nil
        expect(config.messages.length).to be > 0
        expect(config.messages[0].content).to eq('Hello, World!')
        expect(config.enabled).to be true

        expect(config.model).not_to be_nil
        expect(config.model.name).to eq('fakeModel')
        expect(config.model.parameter(:temperature)).to eq(0.5)
        expect(config.model.parameter(:maxTokens)).to eq(4096)
      end

      it 'returns config with messages interpolated as empty when no variables are provided' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fakeModel'),
          messages: []
        )

        config = ai_client.completion_config(key: 'model-config', context:, default:)

        expect(config.messages).not_to be_nil
        expect(config.messages.length).to be > 0
        expect(config.messages[0].content).to eq('Hello, !')
        expect(config.enabled).to be true

        expect(config.model).not_to be_nil
        expect(config.model.name).to eq('fakeModel')
        expect(config.model.parameter(:temperature)).to eq(0.5)
        expect(config.model.parameter(:maxTokens)).to eq(4096)
      end

      it 'handles provider config correctly' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user', name: 'Sandy' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fake-model'),
          messages: []
        )
        variables = { 'name' => 'World' }

        config = ai_client.completion_config(key: 'model-config', context:, default:, variables:)

        expect(config.provider).not_to be_nil
        expect(config.provider.name).to eq('fakeProvider')
        tracker = config.create_tracker
        expect(tracker).not_to be_nil
        expect(tracker.send(:flag_data)).to include(
          modelName: 'fakeModel',
          providerName: 'fakeProvider'
        )
      end

      it 'interpolates context variables in messages using ldctx' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user', name: 'Sandy', last: 'Beaches' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fake-model'),
          messages: []
        )
        variables = { 'name' => 'World' }

        config = ai_client.completion_config(key: 'ctx-interpolation', context:, default:, variables:)

        expect(config.messages).not_to be_nil
        expect(config.messages.length).to be > 0
        expect(config.messages[0].content).to eq('Hello, Sandy! Is your last name Beaches?')
        expect(config.enabled).to be true

        expect(config.model).not_to be_nil
        expect(config.model.name).to eq('fakeModel')
        expect(config.model.parameter(:temperature)).to be_nil
        expect(config.model.parameter(:maxTokens)).to be_nil
        expect(config.model.parameter(:'extra-attribute')).to eq('I can be anything I set my mind/type to')
      end

      it 'interpolates variables from multiple contexts in messages using ldctx' do
        user_context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user', name: 'Sandy' })
        org_context = LaunchDarkly::LDContext.create({ key: 'org-key', kind: 'org', name: 'LaunchDarkly',
                                                       shortname: 'LD' })
        context = LaunchDarkly::LDContext.create_multi([user_context, org_context])
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fake-model'),
          messages: []
        )
        variables = { 'name' => 'World' }

        config = ai_client.completion_config(key: 'multi-ctx-interpolation', context:, default:, variables:)

        expect(config.messages).not_to be_nil
        expect(config.messages.length).to be > 0
        expect(config.messages[0].content).to eq('Hello, Sandy! Do you work for LD?')
        expect(config.enabled).to be true

        expect(config.model).not_to be_nil
        expect(config.model.name).to eq('fakeModel')
        expect(config.model.parameter(:temperature)).to be_nil
        expect(config.model.parameter(:maxTokens)).to be_nil
        expect(config.model.parameter(:'extra-attribute')).to eq('I can be anything I set my mind/type to')
      end

      it 'handles multiple messages and variable interpolation' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fake-model'),
          messages: []
        )
        variables = { 'name' => 'World', 'day' => 'Monday' }

        config = ai_client.completion_config(key: 'multiple-messages', context:, default:, variables:)

        expect(config.messages).not_to be_nil
        expect(config.messages.length).to be > 0
        expect(config.messages[0].content).to eq('Hello, World!')
        expect(config.messages[1].content).to eq('The day is, Monday!')
        expect(config.enabled).to be true

        expect(config.model).not_to be_nil
        expect(config.model.name).to eq('fakeModel')
        expect(config.model.parameter(:temperature)).to eq(0.7)
        expect(config.model.parameter(:maxTokens)).to eq(8192)
      end

      it 'returns disabled config when flag is off' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fake-model'),
          messages: []
        )

        config = ai_client.completion_config(key: 'off-config', context:, default:)

        expect(config.model).not_to be_nil
        expect(config.enabled).to be false
        expect(config.model.name).to eq('fakeModel')
        expect(config.model.parameter(:temperature)).to eq(0.1)
        expect(config.model.parameter(:maxTokens)).to be_nil
      end

      it 'returns disabled config with nil model/messages/provider when initial config is disabled' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: true,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fake-model'),
          messages: []
        )

        config = ai_client.completion_config(key: 'initial-config-disabled', context:, default:)

        expect(config.enabled).to be false
        expect(config.model).to be_nil
        expect(config.messages).to be_nil
        expect(config.provider).to be_nil
      end

      it 'returns enabled config with nil model/messages/provider when initial config is enabled' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        default = LaunchDarkly::Server::AI::AIConfig.new(
          enabled: false,
          model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'fake-model'),
          messages: []
        )

        config = ai_client.completion_config(key: 'initial-config-enabled', context:, default:)

        expect(config.enabled).to be true
        expect(config.model).to be_nil
        expect(config.messages).to be_nil
        expect(config.provider).to be_nil
        tracker = config.create_tracker
        expect(tracker).not_to be_nil
        expect(tracker.send(:flag_data)).to include(
          modelName: '',
          providerName: ''
        )
      end

      it 'uses disabled config when no default value is provided and flag is missing' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })

        config = ai_client.completion_config(key: 'missing-flag', context:)

        expect(config.enabled).to be false
      end

      it 'uses disabled config when nil is explicitly passed as default value and flag is missing' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })

        config = ai_client.completion_config(key: 'missing-flag', context:, default: nil)

        expect(config.enabled).to be false
      end

      it 'create_tracker returns a new tracker with a fresh runId each time' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        config = ai_client.completion_config(key: 'model-config', context:, variables: { 'name' => 'World' })

        tracker1 = config.create_tracker
        tracker2 = config.create_tracker

        expect(tracker1).to be_a(LaunchDarkly::Server::AI::AIConfigTracker)
        expect(tracker2).to be_a(LaunchDarkly::Server::AI::AIConfigTracker)
        expect(tracker1).not_to equal(tracker2)

        run_id1 = tracker1.send(:flag_data)[:runId]
        run_id2 = tracker2.send(:flag_data)[:runId]
        expect(run_id1).not_to eq(run_id2)
        expect(run_id1).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
        expect(run_id2).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
      end

      it 'create_tracker preserves flag metadata across calls' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        config = ai_client.completion_config(key: 'model-config', context:, variables: { 'name' => 'World' })

        tracker = config.create_tracker
        flag_data = tracker.send(:flag_data)

        expect(flag_data[:configKey]).to eq('model-config')
        expect(flag_data[:variationKey]).to eq('abcd')
        expect(flag_data[:version]).to eq(1)
        expect(flag_data[:modelName]).to eq('fakeModel')
        expect(flag_data[:providerName]).to eq('fakeProvider')
      end

      it 'create_tracker returns a tracker even for disabled configs from evaluation' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        config = ai_client.completion_config(key: 'off-config', context:)

        expect(config.enabled).to be false
        tracker = config.create_tracker
        expect(tracker).to be_a(LaunchDarkly::Server::AI::AIConfigTracker)
      end

      it 'round-trips a tracker through a resumption token via client create_tracker' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        config = ai_client.completion_config(key: 'model-config', context:, variables: { 'name' => 'World' })

        tracker = config.create_tracker
        token = tracker.resumption_token
        original_run_id = tracker.send(:flag_data)[:runId]

        restored = ai_client.create_tracker(token: token, context: context)

        expect(restored).to be_a(LaunchDarkly::Server::AI::AIConfigTracker)
        expect(restored.send(:flag_data)[:runId]).to eq(original_run_id)
        expect(restored.send(:flag_data)[:configKey]).to eq('model-config')
        expect(restored.send(:flag_data)[:modelName]).to eq('')
        expect(restored.send(:flag_data)[:providerName]).to eq('')
      end

      it 'each tracker has independent at-most-once tracking' do
        context = LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' })
        config = ai_client.completion_config(key: 'model-config', context:, variables: { 'name' => 'World' })

        tracker1 = config.create_tracker
        tracker2 = config.create_tracker

        tracker1.track_duration(100)
        tracker2.track_duration(200)

        expect(tracker1.summary.duration).to eq(100)
        expect(tracker2.summary.duration).to eq(200)
      end
    end

    describe LaunchDarkly::Server::AI::AIConfig do
      it 'disabled class method returns a disabled AIConfig' do
        config = described_class.disabled
        expect(config).to be_a(described_class)
        expect(config.enabled).to be false
        expect(config.messages).to be_nil
        expect(config.model).to be_nil
      end

      it 'disabled class method returns a new instance each call' do
        first = described_class.disabled
        second = described_class.disabled
        expect(first).not_to be(second)
      end
    end
  end
end

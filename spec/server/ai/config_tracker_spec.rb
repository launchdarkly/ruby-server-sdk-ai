# frozen_string_literal: true

require 'base64'
require 'json'
require 'securerandom'
require 'launchdarkly-server-sdk'
require 'launchdarkly-server-sdk-ai'

RSpec.describe LaunchDarkly::Server::AI::AIConfigTracker do
  let(:td) do
    LaunchDarkly::Integrations::TestData.data_source.update(
      LaunchDarkly::Integrations::TestData.data_source.flag('model_config')
        .variations(
          {
            model: { name: 'fakeModel', parameters: { temperature: 0.5, maxTokens: 4096 },
                     custom: { 'extra-attribute': 'value' } },
            provider: { name: 'fakeProvider' },
            messages: [{ role: 'system', content: 'Hello, {{name}}!' }],
            _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 },
          },
          'green'
        )
        .variation_for_all(0)
    )
  end

  let(:ld_client) do
    config = LaunchDarkly::Config.new(data_source: td, send_events: false)
    LaunchDarkly::LDClient.new('sdk-key', config)
  end

  let(:context) { LaunchDarkly::LDContext.create({ key: 'user-key', kind: 'user' }) }
  let(:tracker_flag_data) {
 { runId: kind_of(String), variationKey: 'test-variation', configKey: 'test-config', version: 1, modelName: 'fakeModel', providerName: 'fakeProvider', modelVersion: 1 } }
  let(:tracker) do
    described_class.new(
      ld_client: ld_client,
      run_id: SecureRandom.uuid,
      config_key: tracker_flag_data[:configKey],
      context: context,
      variation_key: tracker_flag_data[:variationKey],
      version: tracker_flag_data[:version],
      model_name: 'fakeModel',
      provider_name: 'fakeProvider'
    )
  end

  describe '#track_duration' do
    it 'tracks duration with correct event name and data' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        100
      )
      tracker.track_duration(100)
      expect(tracker.summary.duration).to eq(100)
    end
  end

  describe '#track_duration_of' do
    it 'tracks duration of a block and returns its result' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        kind_of(Integer)
      )
      result = tracker.track_duration_of { sleep(0.01) }
      expect(result).to be_within(10).of(0) # Allow some tolerance for sleep timing
      expect(tracker.summary.duration).to be_within(1000).of(10) # Allow some tolerance for sleep timing
    end

    it 'tracks duration even when an exception is raised' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        kind_of(Integer)
      )

      expect do
        tracker.track_duration_of do
          sleep(0.01)
          raise 'Something went wrong'
        end
      end.to raise_error('Something went wrong')
      expect(tracker.summary.duration).to be_within(1000).of(10) # Allow some tolerance for sleep timing
    end
  end

  describe '#track_time_to_first_token' do
    it 'tracks time to first token' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:ttf',
        context,
        tracker_flag_data,
        100
      )
      tracker.track_time_to_first_token(100)
      expect(tracker.summary.time_to_first_token).to eq(100)
    end
  end

  describe '#track_tokens' do
    it 'tracks token usage' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        tracker_flag_data,
        300
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        tracker_flag_data,
        200
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        tracker_flag_data,
        100
      )
      tokens = LaunchDarkly::Server::AI::TokenUsage.new(total: 300, input: 200, output: 100)
      tracker.track_tokens(tokens)
      expect(tracker.summary.usage).to eq(tokens)
    end
  end

  describe '#track_bedrock_metrics' do
    let(:bedrock_result) do
      {
        usage: {
          total_tokens: 300,
          input_tokens: 200,
          output_tokens: 100,
        },
      }
    end

    it 'tracks duration and tokens' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        tracker_flag_data,
        1
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        kind_of(Integer)
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        tracker_flag_data,
        300
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        tracker_flag_data,
        200
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        tracker_flag_data,
        100
      )

      result = tracker.track_bedrock_converse_metrics { bedrock_result }
      expect(result).to eq(bedrock_result)
      expect(tracker.summary).to be_a(LaunchDarkly::Server::AI::MetricSummary)
      expect(tracker.summary.usage).to be_a(LaunchDarkly::Server::AI::TokenUsage)
      expect(tracker.summary.usage.total).to eq(300)
      expect(tracker.summary.usage.input).to eq(200)
      expect(tracker.summary.usage.output).to eq(100)
      expect(tracker.summary.duration).to be_a(Integer)
      expect(tracker.summary.duration).to be >= 0
      expect(tracker.summary.success).to be true
    end

    it 'tracks error for failed operation' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:error',
        context,
        tracker_flag_data,
        1
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        kind_of(Integer)
      )

      expect { tracker.track_bedrock_converse_metrics { raise 'test error' } }.to raise_error('test error')
      expect(tracker.summary.usage).to be_nil
      expect(tracker.summary.duration).to be_a(Integer)
      expect(tracker.summary.duration).to be >= 0
      expect(tracker.summary.success).to be false
    end
  end

  describe '#track_openai_metrics' do
    let(:openai_result) do
      {
        usage: {
          total_tokens: 300,
          prompt_tokens: 200,
          completion_tokens: 100,
        },
      }
    end

    it 'tracks duration and tokens for successful operation' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        kind_of(Integer)
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        tracker_flag_data,
        300
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        tracker_flag_data,
        200
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        tracker_flag_data,
        100
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        tracker_flag_data,
        1
      )

      result = tracker.track_openai_metrics { openai_result }
      expect(result).to eq(openai_result)
      expect(tracker.summary.usage.total).to eq(300)
      expect(tracker.summary.usage.input).to eq(200)
      expect(tracker.summary.usage.output).to eq(100)
      expect(tracker.summary.duration).to be_a(Integer)
      expect(tracker.summary.duration).to be >= 0
      expect(tracker.summary.success).to be true
    end

    it 'tracks error for failed operation' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        kind_of(Integer)
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:error',
        context,
        tracker_flag_data,
        1
      )

      expect { tracker.track_openai_metrics { raise 'test error' } }.to raise_error('test error')
      expect(tracker.summary.usage).to be_nil
      expect(tracker.summary.duration).to be_a(Integer)
      expect(tracker.summary.duration).to be >= 0
      expect(tracker.summary.success).to be false
    end
  end

  describe '#track_feedback' do
    it 'tracks positive feedback' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:feedback:user:positive',
        context,
        tracker_flag_data,
        1
      )
      tracker.track_feedback(kind: :positive)
    end

    it 'tracks negative feedback' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:feedback:user:negative',
        context,
        tracker_flag_data,
        1
      )
      tracker.track_feedback(kind: :negative)
    end
  end

  describe '#track_success' do
    it 'tracks generation and success events' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        tracker_flag_data,
        1
      )
      tracker.track_success
      expect(tracker.summary.success).to be true
    end
  end

  describe '#track_error' do
    it 'tracks generation and error events' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:error',
        context,
        tracker_flag_data,
        1
      )
      tracker.track_error
      expect(tracker.summary.success).to be false
    end

    it 'does not track error if success has already been tracked' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        tracker_flag_data,
        1
      )

      tracker.track_success
      expect(tracker.summary.success).to be true
      tracker.track_error
      expect(tracker.summary.success).to be true
    end
  end

  describe 'at-most-once tracking' do
    it 'only tracks duration once' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        tracker_flag_data,
        100
      ).once
      tracker.track_duration(100)
      tracker.track_duration(200)
      expect(tracker.summary.duration).to eq(100)
    end

    it 'only tracks time to first token once' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:ttf',
        context,
        tracker_flag_data,
        100
      ).once
      tracker.track_time_to_first_token(100)
      tracker.track_time_to_first_token(200)
      expect(tracker.summary.time_to_first_token).to eq(100)
    end

    it 'only tracks tokens once' do
      tokens1 = LaunchDarkly::Server::AI::TokenUsage.new(total: 300, input: 200, output: 100)
      tokens2 = LaunchDarkly::Server::AI::TokenUsage.new(total: 600, input: 400, output: 200)
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        tracker_flag_data,
        300
      ).once
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        tracker_flag_data,
        200
      ).once
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        tracker_flag_data,
        100
      ).once
      tracker.track_tokens(tokens1)
      tracker.track_tokens(tokens2)
      expect(tracker.summary.usage).to eq(tokens1)
    end

    it 'only tracks success once' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        tracker_flag_data,
        1
      ).once
      tracker.track_success
      tracker.track_success
      expect(tracker.summary.success).to be true
    end

    it 'only tracks error once' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:error',
        context,
        tracker_flag_data,
        1
      ).once
      tracker.track_error
      tracker.track_error
      expect(tracker.summary.success).to be false
    end

    it 'only tracks feedback once' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:feedback:user:positive',
        context,
        tracker_flag_data,
        1
      ).once
      tracker.track_feedback(kind: :positive)
      tracker.track_feedback(kind: :negative)
      expect(tracker.summary.feedback).to eq(:positive)
    end
  end

  describe '#summary' do
    it 'returns a summary of tracked metrics' do
      tracker.track_duration(100)
      tracker.track_feedback(kind: :positive)
      tracker.track_tokens(LaunchDarkly::Server::AI::TokenUsage.new(total: 100, input: 50, output: 50))
      tracker.track_success
      tracker.track_time_to_first_token(50)

      expect(tracker.summary.duration).to eq(100)
      expect(tracker.summary.feedback).to eq(:positive)
      expect(tracker.summary.usage.total).to eq(100)
      expect(tracker.summary.usage.input).to eq(50)
      expect(tracker.summary.usage.output).to eq(50)
      expect(tracker.summary.success).to be true
      expect(tracker.summary.time_to_first_token).to eq(50)
    end

    it 'returns nil for untracked metrics' do
      expect(tracker.summary.duration).to be_nil
      expect(tracker.summary.feedback).to be_nil
      expect(tracker.summary.usage).to be_nil
      expect(tracker.summary.success).to be_nil
      expect(tracker.summary.time_to_first_token).to be_nil
    end
  end

  describe '#flag_data' do
    it 'includes runId, model_name, and provider_name in flag data' do
      flag_data = tracker.send(:flag_data)
      expect(flag_data).to include(
        runId: kind_of(String),
        modelName: 'fakeModel',
        providerName: 'fakeProvider',
        modelVersion: 1
      )
      expect(flag_data[:runId]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
    end

    it 'includes modelKey when set' do
      tracker_with_key = described_class.new(
        ld_client: ld_client,
        run_id: SecureRandom.uuid,
        config_key: 'test-config',
        context: context,
        variation_key: 'test-variation',
        version: 1,
        model_name: 'fakeModel',
        provider_name: 'fakeProvider',
        model_key: 'my-model',
        model_version: 2
      )

      flag_data = tracker_with_key.send(:flag_data)
      expect(flag_data[:modelKey]).to eq('my-model')
      expect(flag_data[:modelVersion]).to eq(2)
    end

    it 'omits modelKey when empty' do
      tracker_with_empty_key = described_class.new(
        ld_client: ld_client,
        run_id: SecureRandom.uuid,
        config_key: 'test-config',
        context: context,
        variation_key: 'test-variation',
        version: 1,
        model_name: 'fakeModel',
        provider_name: 'fakeProvider',
        model_key: '',
        model_version: 3
      )

      flag_data = tracker_with_empty_key.send(:flag_data)
      expect(flag_data).not_to have_key(:modelKey)
      expect(flag_data[:modelVersion]).to eq(3)
    end
  end

  describe '#resumption_token' do
    it 'returns a URL-safe base64-encoded JSON string' do
      token = tracker.resumption_token
      decoded = JSON.parse(Base64.urlsafe_decode64(token))

      expect(decoded['runId']).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
      expect(decoded['configKey']).to eq('test-config')
      expect(decoded['variationKey']).to eq('test-variation')
      expect(decoded['version']).to eq(1)
    end

    it 'does not include modelName, providerName, modelKey, or modelVersion' do
      token = tracker.resumption_token
      decoded = JSON.parse(Base64.urlsafe_decode64(token))

      expect(decoded).not_to have_key('modelName')
      expect(decoded).not_to have_key('providerName')
      expect(decoded).not_to have_key('modelKey')
      expect(decoded).not_to have_key('modelVersion')
    end

    it 'contains the same runId as the tracker flag data' do
      flag_data = tracker.send(:flag_data)
      token = tracker.resumption_token
      decoded = JSON.parse(Base64.urlsafe_decode64(token))

      expect(decoded['runId']).to eq(flag_data[:runId])
    end
  end

  describe '.from_resumption_token' do
    it 'reconstructs a tracker that uses the same runId' do
      original_token = tracker.resumption_token
      original_run_id = tracker.send(:flag_data)[:runId]

      restored = described_class.from_resumption_token(
        token: original_token,
        ld_client: ld_client,
        context: context
      )

      expect(restored.send(:flag_data)[:runId]).to eq(original_run_id)
      expect(restored.send(:flag_data)[:configKey]).to eq('test-config')
      expect(restored.send(:flag_data)[:variationKey]).to eq('test-variation')
      expect(restored.send(:flag_data)[:version]).to eq(1)
    end

    it 'sets modelName and providerName to empty strings and modelVersion to 1' do
      token = tracker.resumption_token

      restored = described_class.from_resumption_token(
        token: token,
        ld_client: ld_client,
        context: context
      )

      expect(restored.send(:flag_data)[:modelName]).to eq('')
      expect(restored.send(:flag_data)[:providerName]).to eq('')
      expect(restored.send(:flag_data)[:modelVersion]).to eq(1)
      expect(restored.send(:flag_data)).not_to have_key(:modelKey)
    end

    it 'can track events with the restored tracker' do
      token = tracker.resumption_token
      original_run_id = tracker.send(:flag_data)[:runId]

      restored = described_class.from_resumption_token(
        token: token,
        ld_client: ld_client,
        context: context
      )

      expected_data = {
        runId: original_run_id,
        variationKey: 'test-variation',
        configKey: 'test-config',
        version: 1,
        modelName: '',
        providerName: '',
        modelVersion: 1,
      }

      expect(ld_client).to receive(:track).with(
        '$ld:ai:feedback:user:positive',
        context,
        expected_data,
        1
      )

      restored.track_feedback(kind: :positive)
    end

    it 'round-trips an empty variation_key as an empty string' do
      empty_tracker = described_class.new(
        ld_client: ld_client,
        run_id: SecureRandom.uuid,
        config_key: 'test-config',
        context: context,
        variation_key: '',
        version: 1,
        model_name: 'fakeModel',
        provider_name: 'fakeProvider'
      )

      restored = described_class.from_resumption_token(
        token: empty_tracker.resumption_token,
        ld_client: ld_client,
        context: context
      )

      expect(restored.variation_key).to eq('')
    end
  end

  describe 'completion_config method tracking' do
    it 'calls track with correct parameters when completion_config is called' do
      allow(ld_client).to receive(:track)
      expect(ld_client).to receive(:track).with(
        '$ld:ai:usage:completion-config',
        context,
        'test-config-key',
        1
      )
      allow(ld_client).to receive(:variation).and_return({
        '_ldMeta' => { 'enabled' => true, 'variationKey' => 'test-variation', 'version' => 1 },
        'model' => { 'name' => 'test-model' },
        'provider' => { 'name' => 'test-provider' },
        'messages' => [],
      })

      client = LaunchDarkly::Server::AI::Client.new(ld_client)

      client.completion_config(key: 'test-config-key', context:)
    end
  end
end

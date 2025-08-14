# frozen_string_literal: true

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
  let(:tracker_flag_data) { { variationKey: 'test-variation', configKey: 'test-config', version: 1, modelName: 'fakeModel', providerName: 'fakeProvider' } }
  let(:tracker) do
    described_class.new(
      ld_client: ld_client,
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

    it 'overwrites success with error if both are tracked' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        tracker_flag_data,
        1
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:error',
        context,
        tracker_flag_data,
        1
      )

      tracker.track_success
      expect(tracker.summary.success).to be true
      tracker.track_error
      expect(tracker.summary.success).to be false
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
    it 'includes model_name and provider_name in flag data' do
      expect(tracker.send(:flag_data)).to include(
        modelName: 'fakeModel',
        providerName: 'fakeProvider'
      )
    end
  end

  describe 'config method tracking' do
    it 'calls track with correct parameters when config is called' do
      allow(ld_client).to receive(:track)
      allow(ld_client).to receive(:variation).and_return({
        '_ldMeta' => { 'enabled' => true, 'variationKey' => 'test-variation', 'version' => 1 },
        'model' => { 'name' => 'test-model' },
        'provider' => { 'name' => 'test-provider' },
        'messages' => [],
      })

      client = LaunchDarkly::Server::AI::Client.new(ld_client)
      default_value = LaunchDarkly::Server::AI::AIConfig.new(enabled: false)

      client.config('test-config-key', context, default_value)

      expect(ld_client).to have_received(:track).with(
        '$ld:ai:config:function:single',
        context,
        'test-config-key',
        1
      )
    end
  end
end

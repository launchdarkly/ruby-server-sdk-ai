# frozen_string_literal: true

require 'ldclient-rb'
require 'ldclient-ai'

RSpec.describe LaunchDarkly::AI::LDAIConfigTracker do
  let(:td) do
    LaunchDarkly::Integrations::TestData.data_source.update(
      LaunchDarkly::Integrations::TestData.data_source.flag('model_config')
        .variations(
          {
            model: { name: 'fakeModel', parameters: { temperature: 0.5, maxTokens: 4096 },
                     custom: { 'extra-attribute': 'value' } },
            provider: { name: 'fakeProvider' },
            messages: [{ role: 'system', content: 'Hello, {{name}}!' }],
            _ldMeta: { enabled: true, variationKey: 'abcd', version: 1 }
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

  let(:context) { LaunchDarkly::LDContext.create({ key: 'test-user', kind: 'user' }) }
  let(:tracker) do
    described_class.new(
      ld_client: ld_client,
      config_key: 'test-config',
      context: context,
      variation_key: 'test-variation',
      version: 1
    )
  end

  describe '#track_duration' do
    it 'tracks duration with correct event name and data' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        100
      )
      tracker.track_duration(100)
    end
  end

  describe '#track_duration_of' do
    it 'tracks duration of a block and returns its result' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        kind_of(Integer)
      )
      result = tracker.track_duration_of { 'test result' }
      expect(result).to eq('test result')
    end
  end

  describe '#track_feedback' do
    it 'tracks positive feedback' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:feedback:user:positive',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      tracker.track_feedback(kind: :positive)
    end

    it 'tracks negative feedback' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:feedback:user:negative',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      tracker.track_feedback(kind: :negative)
    end
  end

  describe '#track_success' do
    it 'tracks generation and success events' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      tracker.track_success
    end
  end

  describe '#track_error' do
    it 'tracks generation and error events' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:error',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      tracker.track_error
    end
  end

  describe '#track_tokens' do
    it 'tracks total tokens' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        300
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        200
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        100
      )
      tokens = LaunchDarkly::AI::TokenUsage.new(total: 300, input: 200, output: 100)
      tracker.track_tokens(tokens)
      expect(tracker.summary.usage).to eq(tokens)
    end

    it 'tracks all token types' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        100
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        50
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        50
      )
      tracker.track_tokens(total: 100, input: 50, output: 50)
    end
  end

  describe '#track_openai_metrics' do
    let(:openai_result) do
      double('OpenAIResult', usage: double(
        total_tokens: 100,
        prompt_tokens: 50,
        completion_tokens: 50
      ))
    end

    it 'tracks duration and tokens for successful operation' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        kind_of(Integer)
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        100
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        50
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        50
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:success',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )

      result = tracker.track_openai_metrics { openai_result }
      expect(result).to eq(openai_result)
    end

    it 'tracks error for failed operation' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        kind_of(Integer)
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:generation:error',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        1
      )

      expect { tracker.track_openai_metrics { raise 'test error' } }.to raise_error('test error')
    end
  end

  describe '#track_bedrock_metrics' do
    let(:bedrock_result) do
      double('BedrockResult', usage: double(
        total_tokens: 100,
        input_tokens: 50,
        output_tokens: 50
      ))
    end

    it 'tracks duration and tokens' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:duration:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        kind_of(Integer)
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:total',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        100
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:input',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        50
      )
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:output',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        50
      )

      result = tracker.track_bedrock_metrics { bedrock_result }
      expect(result).to eq(bedrock_result)
    end
  end

  describe '#track_time_to_first_token' do
    it 'tracks time to first token' do
      expect(ld_client).to receive(:track).with(
        '$ld:ai:tokens:ttf',
        context,
        { variationKey: 'test-variation', configKey: 'test-config', version: 1 },
        100
      )
      tracker.track_time_to_first_token(100)
    end
  end

  describe '#summary' do
    it 'returns a summary of tracked metrics' do
      tracker.track_duration(100)
      tracker.track_feedback(kind: :positive)
      tracker.track_tokens(total: 100, input: 50, output: 50)
      tracker.track_success
      tracker.track_time_to_first_token(50)

      expect(tracker.summary).to eq({
                                      duration: 100,
                                      feedback: :positive,
                                      tokens: { total: 100, input: 50, output: 50 },
                                      success: true,
                                      time_to_first_token: 50
                                    })
    end

    it 'returns nil for untracked metrics' do
      expect(tracker.summary).to eq({
                                      duration: nil,
                                      feedback: nil,
                                      tokens: nil,
                                      success: nil,
                                      time_to_first_token: nil
                                    })
    end
  end
end

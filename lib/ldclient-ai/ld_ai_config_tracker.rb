# frozen_string_literal: true

require 'ldclient-rb'

module LaunchDarkly
  module AI
    class LDAIConfigTracker
      attr_reader :ld_client, :config_key, :context, :variation_key, :version

      def initialize(ld_client:, config_key:, context:, variation_key:, version:)
        @ld_client = ld_client
        @config_key = config_key
        @context = context
        @variation_key = variation_key
        @version = version
        @duration = nil
        @feedback = nil
        @tokens = nil
        @success = nil
        @time_to_first_token = nil
      end

      def track_duration(duration)
        @duration = duration
        @ld_client.track(
          '$ld:ai:duration:total',
          @context,
          { variationKey: @variation_key, configKey: @config_key },
          duration
        )
      end

      def track_duration_of
        start_time = Time.now
        result = yield
        duration = ((Time.now - start_time) * 1000).to_i
        track_duration(duration)
        result
      end

      def track_feedback(kind:)
        @feedback = kind
        event_name = kind == :positive ? '$ld:ai:feedback:user:positive' : '$ld:ai:feedback:user:negative'
        @ld_client.track(
          event_name,
          @context,
          { variationKey: @variation_key, configKey: @config_key },
          1
        )
      end

      def track_success
        @success = true
        @ld_client.track(
          '$ld:ai:generation',
          @context,
          { variationKey: @variation_key, configKey: @config_key },
          1
        )
        @ld_client.track(
          '$ld:ai:generation:success',
          @context,
          { variationKey: @variation_key, configKey: @config_key },
          1
        )
      end

      def track_error
        @success = false
        @ld_client.track(
          '$ld:ai:generation',
          @context,
          { variationKey: @variation_key, configKey: @config_key },
          1
        )
        @ld_client.track(
          '$ld:ai:generation:error',
          @context,
          { variationKey: @variation_key, configKey: @config_key },
          1
        )
      end

      def track_tokens(total: nil, input: nil, output: nil)
        @tokens = { total: total, input: input, output: output }
        if total
          @ld_client.track(
            '$ld:ai:tokens:total',
            @context,
            { variationKey: @variation_key, configKey: @config_key },
            total
          )
        end
        if input
          @ld_client.track(
            '$ld:ai:tokens:input',
            @context,
            { variationKey: @variation_key, configKey: @config_key },
            input
          )
        end
        if output
          @ld_client.track(
            '$ld:ai:tokens:output',
            @context,
            { variationKey: @variation_key, configKey: @config_key },
            output
          )
        end
      end

      def track_openai_metrics
        start_time = Time.now
        result = yield
        duration = ((Time.now - start_time) * 1000).to_i
        track_duration(duration)
        track_success
        if result.usage
          track_tokens(
            total: result.usage.total_tokens,
            input: result.usage.prompt_tokens,
            output: result.usage.completion_tokens
          )
        end
        result
      rescue StandardError => e
        track_error
        raise e
      end

      def track_bedrock_metrics
        start_time = Time.now
        result = yield
        duration = ((Time.now - start_time) * 1000).to_i
        track_duration(duration)
        if result.usage
          track_tokens(
            total: result.usage.total_tokens,
            input: result.usage.input_tokens,
            output: result.usage.output_tokens
          )
        end
        result
      end

      def track_time_to_first_token(duration)
        @time_to_first_token = duration
        @ld_client.track(
          '$ld:ai:tokens:ttf',
          @context,
          { variationKey: @variation_key, configKey: @config_key },
          duration
        )
      end

      def get_summary
        {
          duration: @duration,
          feedback: @feedback,
          tokens: @tokens,
          success: @success,
          time_to_first_token: @time_to_first_token
        }
      end
    end
  end
end 
# frozen_string_literal: true

require 'base64'
require 'json'
require 'ldclient-rb'

module LaunchDarkly
  module Server
    module AI
      #
      # Tracks token usage for AI operations.
      #
      class TokenUsage
        attr_reader :total, :input, :output

        #
        # @param total [Integer] Total number of tokens used.
        # @param input [Integer] Number of tokens in the prompt.
        # @param output [Integer] Number of tokens in the completion.
        #
        def initialize(total: nil, input: nil, output: nil)
          @total = total
          @input = input
          @output = output
        end
      end

      #
      # Summary of metrics which have been tracked.
      #
      class MetricSummary
        attr_accessor :duration, :success, :feedback, :usage, :time_to_first_token

        def initialize
          @duration = nil
          @success = nil
          @feedback = nil
          @usage = nil
          @time_to_first_token = nil
        end
      end

      #
      # The AIConfigTracker class is used to track AI configuration usage.
      #
      class AIConfigTracker
        attr_reader :ld_client, :config_key, :context, :variation_key, :version, :summary, :model_name, :provider_name

        #
        # Initialize a new AIConfigTracker instance.
        #
        # @param ld_client [LDClient] The LaunchDarkly client instance
        # @param variation_key [String] The variation key from the flag evaluation
        # @param config_key [String] The configuration key
        # @param version [Integer] The version number
        # @param model_name [String] The name of the AI model being used
        # @param provider_name [String] The name of the AI provider
        # @param context [LDContext] The context used for the flag evaluation
        #
        def initialize(ld_client:, variation_key:, config_key:, version:, model_name:, provider_name:, context:, run_id:)
          @ld_client = ld_client
          @variation_key = variation_key
          @config_key = config_key
          @version = version
          @model_name = model_name
          @provider_name = provider_name
          @context = context
          @summary = MetricSummary.new
          @run_id = run_id
          @tracked_duration = false
          @tracked_time_to_first_token = false
          @tracked_tokens = false
          @tracked_success = nil
          @tracked_feedback = false
          @logger = LaunchDarkly::Server::AI.default_logger
        end

        #
        # Returns a URL-safe Base64-encoded JSON token that can be used to reconstruct
        # a tracker in a different process (e.g. for deferred feedback).
        #
        # The token contains: runId, configKey, variationKey, version.
        # modelName and providerName are NOT included.
        #
        # @return [String] the resumption token
        #
        def resumption_token
          payload = {
            runId: @run_id,
            configKey: @config_key,
            variationKey: @variation_key,
            version: @version,
          }
          Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
        end

        #
        # Reconstructs a tracker from a resumption token.
        #
        # @param token [String] A URL-safe Base64-encoded JSON resumption token
        # @param ld_client [LDClient] The LaunchDarkly client instance
        # @param context [LDContext] The context for track events
        # @return [AIConfigTracker] A new tracker instance
        #
        def self.from_resumption_token(token:, ld_client:, context:)
          json = Base64.urlsafe_decode64(token)
          payload = JSON.parse(json)

          new(
            ld_client: ld_client,
            run_id: payload['runId'],
            config_key: payload['configKey'],
            variation_key: payload.fetch('variationKey', ''),
            version: payload['version'],
            model_name: '',
            provider_name: '',
            context: context
          )
        end

        #
        # Track the duration of an AI operation
        #
        # @param duration [Integer] The duration in milliseconds
        #
        def track_duration(duration)
          if @tracked_duration
            @logger&.warn("Duration has already been tracked for this execution.")
            return
          end
          @tracked_duration = true
          @summary.duration = duration
          @ld_client.track(
            '$ld:ai:duration:total',
            @context,
            flag_data,
            duration
          )
        end

        #
        # Track the duration of a block of code
        #
        # @yield The block to measure
        # @return The result of the block
        #
        def track_duration_of(&block)
          start_time = Time.now
          yield
        ensure
          duration = ((Time.now - start_time) * 1000).to_i
          track_duration(duration)
        end

        #
        # Track time to first token
        #
        # @param duration [Integer] The duration in milliseconds
        #
        def track_time_to_first_token(time_to_first_token)
          if @tracked_time_to_first_token
            @logger&.warn("Time to first token has already been tracked for this execution.")
            return
          end
          @tracked_time_to_first_token = true
          @summary.time_to_first_token = time_to_first_token
          @ld_client.track(
            '$ld:ai:tokens:ttf',
            @context,
            flag_data,
            time_to_first_token
          )
        end

        #
        # Track user feedback
        #
        # @param kind [Symbol] The kind of feedback (:positive or :negative)
        #
        def track_feedback(kind:)
          if @tracked_feedback
            @logger&.warn("Feedback has already been tracked for this execution.")
            return
          end
          @tracked_feedback = true
          @summary.feedback = kind
          event_name = kind == :positive ? '$ld:ai:feedback:user:positive' : '$ld:ai:feedback:user:negative'
          @ld_client.track(
            event_name,
            @context,
            flag_data,
            1
          )
        end

        #
        # Track a successful AI generation
        #
        def track_success
          unless @tracked_success.nil?
            @logger&.warn("Success or error has already been tracked for this execution.")
            return
          end
          @tracked_success = true
          @summary.success = true
          @ld_client.track(
            '$ld:ai:generation:success',
            @context,
            flag_data,
            1
          )
        end

        #
        # Track an error in AI generation
        #
        def track_error
          unless @tracked_success.nil?
            @logger&.warn("Success or error has already been tracked for this execution.")
            return
          end
          @tracked_success = false
          @summary.success = false
          @ld_client.track(
            '$ld:ai:generation:error',
            @context,
            flag_data,
            1
          )
        end

        #
        # Track token usage
        #
        # @param token_usage [TokenUsage] An object containing token usage details
        #
        def track_tokens(token_usage)
          if @tracked_tokens
            @logger&.warn("Tokens have already been tracked for this execution.")
            return
          end
          @tracked_tokens = true
          @summary.usage = token_usage
          if token_usage.total.positive?
            @ld_client.track(
              '$ld:ai:tokens:total',
              @context,
              flag_data,
              token_usage.total
            )
          end
          if token_usage.input.positive?
            @ld_client.track(
              '$ld:ai:tokens:input',
              @context,
              flag_data,
              token_usage.input
            )
          end
          return unless token_usage.output.positive?

          @ld_client.track(
            '$ld:ai:tokens:output',
            @context,
            flag_data,
            token_usage.output
          )
        end

        #
        # Track OpenAI-specific operations.
        # This method tracks the duration, token usage, and success/error status.
        # If the provided block raises, this method will also raise.
        # A failed operation will not have any token usage data.
        #
        # @yield The block to track.
        # @return The result of the tracked block.
        #
        def track_openai_metrics(&block)
          result = track_duration_of(&block)
          track_success
          track_tokens(openai_to_token_usage(result[:usage])) if result[:usage]
          result
        rescue StandardError
          track_error
          raise
        end

        #
        # Track AWS Bedrock conversation operations.
        # This method tracks the duration, token usage, and success/error status.
        #
        # @yield The block to track.
        # @return [Hash] The original response hash.
        #
        def track_bedrock_converse_metrics(&block)
          result = track_duration_of(&block)
          track_success
          track_tokens(bedrock_to_token_usage(result[:usage])) if result[:usage]
          result
        rescue StandardError
          track_error
          raise
        end

        private def flag_data
          {
            runId: @run_id,
            variationKey: @variation_key,
            configKey: @config_key,
            version: @version,
            modelName: @model_name,
            providerName: @provider_name,
          }
        end

        private def openai_to_token_usage(usage)
          TokenUsage.new(
            total: usage[:total_tokens] || usage['total_tokens'],
            input: usage[:prompt_tokens] || usage['prompt_tokens'],
            output: usage[:completion_tokens] || usage['completion_tokens']
          )
        end

        private def bedrock_to_token_usage(usage)
          TokenUsage.new(
            total: usage[:total_tokens] || usage['total_tokens'],
            input: usage[:input_tokens] || usage['input_tokens'],
            output: usage[:output_tokens] || usage['output_tokens']
          )
        end
      end
    end
  end
end

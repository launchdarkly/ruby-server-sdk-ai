# frozen_string_literal: true

require 'ldclient-rb'
require 'mustache'

module LaunchDarkly
  #
  # Namespace for the LaunchDarkly AI SDK.
  #
  module AI
    # The AIConfig class represents an AI configuration.
    class AIConfig
      attr_reader :enabled, :messages, :variables, :tracker

      def initialize(enabled: false, messages: nil, variables: nil, tracker: nil)
        @enabled = enabled
        @messages = messages
        @variables = variables
        @tracker = tracker
      end

      def self.default
        AIConfig.new(enabled: false)
      end

      def to_h
        {
          enabled: @enabled || false,
          messages: @messages,
          variables: @variables,
          tracker: @tracker
        }
      end
    end

    # The LDAIConfigTracker class is used to track AI configuration.
    class LDAIConfigTracker
      attr_reader :ld_client, :config_key, :context, :variation_key, :version

      def initialize(ld_client:, config_key:, context:, variation_key:, version:)
        @ld_client = ld_client
        @config_key = config_key
        @context = context
        @variation_key = variation_key
        @version = version
      end

      def track
        @ld_client.track('ai_config_used', @context, nil, {
                           configKey: @config_key,
                           variationKey: @variation_key,
                           version: @version
                         })
      end
    end

    # The LDAIClient class is the main entry point for the LaunchDarkly AI SDK.
    class LDAIClient
      attr_reader :logger, :ld_client

      def initialize(ld_client)
        raise ArgumentError, 'LDClient instance is required' unless ld_client.is_a?(LaunchDarkly::LDClient)

        @ld_client = ld_client
        @logger = LaunchDarkly::AI.default_logger
      end

      # Retrieves the AIConfig
      # @param key [String] The key of the configuration flag
      # @param context [LDContext] The context used when evaluating the flag
      # @param default_value [AIConfig] The default value to use if the flag is not found
      # @param variables [Hash] Optional variables for rendering messages
      # @return [AIConfig] An AIConfig instance containing the configuration data
      def config(key, context, default_value = AIConfig.default, variables: nil)
        variation = @ld_client.variation(key, context, default_value.to_h)

        # Build variables dictionary for rendering messages
        all_variables = {}

        unless variables.nil?
          variables.each do |k, v|
            all_variables[k] = v
          end
        end
        all_variables['ldctx'] = context.keys

        # Render messages if they exist
        messages = nil
        if variation.key?('messages')
          messages = variation['messages'].map do |message|
            message['content'] = Mustache.render(message['content'], all_variables) if message.key?('content')
            message
          end
        end

        tracker = LDAIConfigTracker.new(
          ld_client: @ld_client,
          config_key: key,
          context: context,
          variation_key: key,
          version: 1
        )

        AIConfig.new(
          enabled: variation['enabled'] || false,
          messages: messages,
          variables: all_variables,
          tracker: tracker
        )
      end
    end
  end
end

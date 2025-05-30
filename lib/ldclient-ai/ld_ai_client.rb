# frozen_string_literal: true

require 'ldclient-rb'
require 'mustache'

module LaunchDarkly
  #
  # Namespace for the LaunchDarkly AI SDK.
  #
  module AI
    # The LDAIConfigTracker class is used to track AI configuration.
    class AIConfig
      attr_reader :enabled, :messages, :variables, :tracker

      def initialize(enabled: false, messages: nil, variables: nil, tracker: nil)
        @enabled = enabled
        @messages = messages
        @variables = variables
        @tracker = tracker
      end

      def default
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
      # @param default_value [AIConfig]
      # @param variables [] Optional variables for rendering messages
      # @return [AIConfig] An AIConfig instance containing the configuration data
      def config(key, context, default_value, variables: nil)
        variation = @ld_client.variation(key, context, default_value.to_h)

        # Build variables dictionary for rendering messages
        all_variables = {}

        if variables.nil?
          variables.each do |key, value|
            all_variables[key] = value
          end
        end
        all_variables['ldctx'] = context.to_h

        # Render messages if they exist
        messages = nil
        if variation.key?('messages')
          messages = variation['messages'].map do |message|
            message['content'] = Mustache.render(message['content'], variables) if message.key?('content')
            message
          end
        end

        tracker = LDAIConfigTracker.new(
          ld_client: @ld_client,
          config_key: config_key,
          context: context,
          variation_key: config_key,
          version: 1
        )

        AIConfig.new(
          enabled: result['_ldMeta']['enabled'],
          messages: messages,
          variables: variables,
          tracker: tracker
        )
      end
    end
  end
end

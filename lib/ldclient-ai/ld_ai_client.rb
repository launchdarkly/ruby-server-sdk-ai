# frozen_string_literal: true

require 'ldclient-rb'
require 'mustache'

module LaunchDarkly
  #
  # Namespace for the LaunchDarkly AI SDK.
  #
  module AI
    class LDAIClient
      attr_reader :logger
      attr_reader :ld_client

      def initialize(ld_client)
        raise ArgumentError, 'LDClient instance is required' unless ld_client.is_a?(LaunchDarkly::LDClient)

        @ld_client = ld_client
        @logger = LaunchDarkly::AI.default_logger
      end

      # Retrieves a configuration and returns a tracker for monitoring its usage
      # @param config_key [String] The key of the configuration flag
      # @param context [LDContext] The context used when evaluating the flag
      # @return [LDAIConfigTracker] A tracker instance for monitoring the configuration usage
      def config(config_key, context)
        result = @ld_client.json_variation(config_key, context, {})
        unless result.is_a?(Hash)
          raise ArgumentError, 'Result must be a dictionary'
        end

        unless result.key?('_ldMeta')
          raise ArgumentError, 'Result must contain _ldMeta'
        end

        unless result['_ldMeta'].key?('enabled')
          raise ArgumentError, 'Result must contain _ldMeta.enabled'
        end

        # Build variables dictionary for rendering messages
        variables = {}
        result.each do |key, value|
          next if key == '_ldMeta'
          variables[key] = value
        end

        # Render messages if they exist
        if result.key?('messages')
          result['messages'] = result['messages'].map do |message|
            if message.key?('content')
              message['content'] = Mustache.render(message['content'], variables)
            end
            message
          end
        end

        LDAIConfigTracker.new(
          ld_client: @ld_client,
          config_key: config_key,
          context: context,
          variation_key: config_key,
          version: 1
        )
      end
    end
  end
end
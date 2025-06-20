# frozen_string_literal: true

require 'ldclient-rb'
require 'mustache'
require_relative 'ai_config_tracker'

module LaunchDarkly
  #
  # Namespace for the LaunchDarkly Server SDK
  #
  module Server
    #
    # Namespace for the LaunchDarkly Server AI SDK.
    #
    module AI
      #
      # Holds AI role and content.
      #
      class Message
        attr_reader :role, :content

        def initialize(role, content)
          @role = role
          @content = content
        end

        def to_h
          {
            role: @role,
            content: @content,
          }
        end
      end

      #
      # The ModelConfig class represents an AI model configuration.
      #
      class ModelConfig
        attr_reader :name

        def initialize(name:, parameters: {}, custom: {})
          @name = name
          @parameters = parameters
          @custom = custom
        end

        #
        # Retrieve model-specific parameters.
        #
        # Accessing a named, typed attribute (e.g. name) will result in the call
        # being delegated to the appropriate property.
        #
        # @param key [String] The parameter key to retrieve
        # @return [Object, nil] The parameter value or nil if not found
        #
        def parameter(key)
          return @name if key == 'name'
          return nil unless @parameters.is_a?(Hash)

          @parameters[key]
        end

        #
        # Retrieve customer provided data.
        #
        # @param key [String] The custom key to retrieve
        # @return [Object, nil] The custom value or nil if not found
        #
        def custom(key)
          return nil unless @custom.is_a?(Hash)

          @custom[key]
        end

        def to_h
          {
            name: @name,
            parameters: @parameters,
            custom: @custom,
          }
        end
      end

      #
      # Configuration related to the provider.
      #
      class ProviderConfig
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_h
          {
            name: @name,
          }
        end
      end

      #
      # The AIConfig class represents an AI configuration.
      #
      class AIConfig
        attr_reader :enabled, :messages, :variables, :tracker, :model, :provider

        def initialize(enabled: nil, model: nil, messages: nil, tracker: nil, provider: nil)
          @enabled = enabled
          @messages = messages
          @tracker = tracker
          @model = model
          @provider = provider
        end

        def to_h
          {
            _ldMeta: {
              enabled: @enabled || false,
            },
            messages: @messages.is_a?(Array) ? @messages.map { |msg| msg&.to_h } : nil,
            model: @model&.to_h,
            provider: @provider&.to_h,
          }
        end
      end

      #
      # The Client class is the main entry point for the LaunchDarkly AI SDK.
      #
      class Client
        attr_reader :logger, :ld_client

        def initialize(ld_client)
          raise ArgumentError, 'LDClient instance is required' unless ld_client.is_a?(LaunchDarkly::LDClient)

          @ld_client = ld_client
          @logger = LaunchDarkly::Server::AI.default_logger
        end

        #
        # Retrieves the AIConfig
        #
        # @param config_key [String] The key of the configuration flag
        # @param context [LDContext] The context used when evaluating the flag
        # @param default_value [AIConfig] The default value to use if the flag is not found
        # @param variables [Hash] Optional variables for rendering messages
        # @return [AIConfig] An AIConfig instance containing the configuration data
        #
        def config(config_key, context, default_value = nil, variables = nil)
          variation = @ld_client.variation(
            config_key,
            context,
            default_value.respond_to?(:to_h) ? default_value.to_h : nil
          )

          all_variables = variables ? variables.dup : {}
          all_variables[:ldctx] = context.to_h

          # Process messages and provider configuration
          messages = nil
          if variation[:messages].is_a?(Array) && variation[:messages].all? { |msg| msg.is_a?(Hash) }
            messages = variation[:messages].map do |message|
              next unless message[:content].is_a?(String)

              Message.new(
                message[:role],
                Mustache.render(message[:content], all_variables)
              )
            end
          end

          if (provider_config = variation[:provider]) && provider_config.is_a?(Hash)
            provider_config = ProviderConfig.new(provider_config.fetch(:name, ''))
          end

          if (model = variation[:model]) && model.is_a?(Hash)
            parameters = variation[:model][:parameters]
            custom = variation[:model][:custom]
            model = ModelConfig.new(
              name: variation[:model][:name],
              parameters: parameters,
              custom: custom
            )
          end

          tracker = LaunchDarkly::Server::AI::AIConfigTracker.new(
            ld_client: @ld_client,
            variation_key: variation.dig(:_ldMeta, :variationKey) || '',
            config_key: config_key,
            version: variation.dig(:_ldMeta, :version) || 1,
            context: context
          )

          AIConfig.new(
            enabled: variation.dig(:_ldMeta, :enabled) || false,
            messages: messages,
            tracker: tracker,
            model: model,
            provider: provider_config
          )
        end
      end
    end
  end
end

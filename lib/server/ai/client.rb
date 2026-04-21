# frozen_string_literal: true

require 'ldclient-rb'
require 'mustache'
require 'securerandom'
require_relative 'ai_config_tracker'
require_relative 'sdk_info'

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
      # The AIConfigDefault class represents a user-provided fallback AI configuration.
      #
      # Pass an instance of this class as the +default:+ parameter to
      # {Client#completion_config} to control the fallback values when a flag
      # is not found or cannot be evaluated.
      #
      class AIConfigDefault
        attr_reader :enabled, :messages, :model, :provider

        def self.disabled
          new(enabled: false)
        end

        def initialize(enabled: false, model: nil, messages: nil, provider: nil)
          @enabled = enabled
          @messages = messages
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
      # The AIConfig class represents an AI configuration returned by the SDK.
      #
      # Instances are created by {Client#completion_config} and always include
      # a {#create_tracker} factory. Do not instantiate directly — use
      # {AIConfigDefault} for fallback values.
      #
      class AIConfig
        attr_reader :enabled, :messages, :model, :provider

        def initialize(tracker_factory:, enabled: nil, model: nil, messages: nil, provider: nil)
          @enabled = enabled
          @messages = messages
          @tracker_factory = tracker_factory
          @model = model
          @provider = provider
        end

        #
        # Creates a new tracker with a fresh runId for tracking a single AI execution.
        #
        # @return [AIConfigTracker] a new tracker instance
        #
        def create_tracker
          @tracker_factory.call
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
      TRACK_SDK_INFO = '$ld:ai:sdk:info'
      TRACK_USAGE_COMPLETION_CONFIG = '$ld:ai:usage:completion-config'

      INIT_TRACK_CONTEXT = LaunchDarkly::LDContext.create({
        kind: 'ld_ai',
        key: 'ld-internal-tracking',
        anonymous: true,
      })

      class Client
        attr_reader :logger, :ld_client

        def initialize(ld_client)
          raise ArgumentError, 'LDClient instance is required' unless ld_client.is_a?(LaunchDarkly::LDClient)

          @ld_client = ld_client
          @logger = LaunchDarkly::Server::AI.default_logger

          @ld_client.track(
            TRACK_SDK_INFO,
            INIT_TRACK_CONTEXT,
            {
              aiSdkName: LaunchDarkly::Server::AI::SDK_NAME,
              aiSdkVersion: LaunchDarkly::Server::AI::VERSION,
              aiSdkLanguage: LaunchDarkly::Server::AI::SDK_LANGUAGE,
            },
            1
          )
        end

        #
        # Retrieves the AIConfig
        #
        # @param key [String] The key of the configuration flag
        # @param context [LDContext] The context used when evaluating the flag
        # @param default [AIConfigDefault] The default value to use if the flag is not found
        # @param variables [Hash] Optional variables for rendering messages
        # @return [AIConfig] An AIConfig instance containing the configuration data
        #
        def completion_config(key:, context:, default: nil, variables: nil)
          @ld_client.track(TRACK_USAGE_COMPLETION_CONFIG, context, key, 1)

          _completion_config(key:, context:, default: default || AIConfigDefault.disabled, variables:)
        end

        #
        # Reconstructs a tracker from a resumption token, allowing deferred tracking
        # (e.g. feedback from a different process).
        #
        # @param token [String] A resumption token obtained from AIConfigTracker#resumption_token
        # @param context [LDContext] The context for track events
        # @return [AIConfigTracker] A new tracker instance
        #
        def create_tracker(token:, context:)
          AIConfigTracker.from_resumption_token(token: token, ld_client: @ld_client, context: context)
        end

        # @deprecated Use {#completion_config} instead.
        def config(key:, context:, default: nil, variables: nil)
          warn '[DEPRECATION] `config` is deprecated. Use `completion_config` instead.'
          completion_config(key:, context:, default:, variables:)
        end

        private

        def _completion_config(key:, context:, default:, variables: nil)
          variation = @ld_client.variation(
            key,
            context,
            default.respond_to?(:to_h) ? default.to_h : nil
          )

          all_variables = variables ? variables.dup : {}
          all_variables[:ldctx] = context.to_h

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

          variation_key = variation.dig(:_ldMeta, :variationKey) || ''
          version = variation.dig(:_ldMeta, :version) || 1
          model_name = model&.name || ''
          provider_name = provider_config&.name || ''

          tracker_factory = lambda {
            LaunchDarkly::Server::AI::AIConfigTracker.new(
              ld_client: @ld_client,
              run_id: SecureRandom.uuid,
              variation_key: variation_key,
              config_key: key,
              version: version,
              model_name: model_name,
              provider_name: provider_name,
              context: context
            )
          }

          AIConfig.new(
            enabled: variation.dig(:_ldMeta, :enabled) || false,
            messages:,
            tracker_factory:,
            model:,
            provider: provider_config
          )
        end
      end
    end
  end
end

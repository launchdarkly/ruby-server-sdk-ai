# frozen_string_literal: true

require 'ldclient-rb'

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
    end
  end
end
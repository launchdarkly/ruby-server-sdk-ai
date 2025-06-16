# frozen_string_literal: true

require 'logger'
require 'mustache'

require 'server/ai/version'
require 'server/ai/client'
require 'server/ai/config_tracker'

module LaunchDarkly
  module Server
    #
    # Namespace for the LaunchDarkly AI SDK.
    #
    module AI
      #
      # @return [Logger] the Rails logger if in Rails, or a default Logger at WARN level otherwise
      #
      def self.default_logger
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger
        else
          log = ::Logger.new($stdout)
          log.level = ::Logger::WARN
          log
        end
      end
    end
  end
end

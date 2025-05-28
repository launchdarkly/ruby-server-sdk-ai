# frozen_string_literal: true

require "ldclient-ai/ld_ai_client"
require 'ldclient-ai/version'
require 'logger'

module LaunchDarkly
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

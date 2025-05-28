# frozen_string_literal: true

require 'launchdarkly_server_sdk_ai'

RSpec.describe LaunchDarkly::AI do
  it 'has a version number' do
    expect(LaunchDarkly::AI::VERSION).not_to be nil
  end

  it 'returns a logger' do
    logger = LaunchDarkly::AI.default_logger
    expect(logger).to be_a(Logger)
    expect(logger.level).to eq(Logger::WARN)
  end
end

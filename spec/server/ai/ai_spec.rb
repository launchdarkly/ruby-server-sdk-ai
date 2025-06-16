# frozen_string_literal: true

require 'launchdarkly-server-sdk-ai'

RSpec.describe LaunchDarkly::Server::AI do
  it 'has a version number' do
    expect(LaunchDarkly::Server::AI::VERSION).not_to be nil
  end

  it 'returns a logger' do
    logger = LaunchDarkly::Server::AI.default_logger
    expect(logger).to be_a(Logger)
    expect(logger.level).to eq(Logger::WARN)
  end
end

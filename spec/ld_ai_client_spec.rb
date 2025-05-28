# frozen_string_literal: true

require 'launchdarkly_server_sdk_ai'

RSpec.describe LaunchDarkly::AI::LDAIClient do
  it '1.2.1 The SDK MUST provide access to an LDAIClient' do
    ld_client = LaunchDarkly::LDClient.new('sdk-key-123abc')
    ai_client = LaunchDarkly::AI::LDAIClient.new(ld_client)
    expect(ai_client).to be_a(LaunchDarkly::AI::LDAIClient)
  end
  it '1.2.2 The LDAIClient MUST be provided a fully configured LDClient instance at instantiation.' do
    expect { LaunchDarkly::AI::LDAIClient.new(nil) }.to raise_error(ArgumentError, 'LDClient instance is required')
  end
end

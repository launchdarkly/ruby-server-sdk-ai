# frozen_string_literal: true

require 'launchdarkly-server-sdk'
require 'launchdarkly-server-sdk-ai'
require 'openai'

# Set sdk_key to your LaunchDarkly SDK key.
sdk_key = ENV['LAUNCHDARKLY_SDK_KEY']

# Set config_key to the AI Config key you want to evaluate.
ai_config_key = ENV['LAUNCHDARKLY_AI_CONFIG_KEY'] || 'sample-ai-config'

# Set openai_api_key to your OpenAI API key.
openai_api_key = ENV['OPENAI_API_KEY']

if sdk_key.nil? || sdk_key.empty?
  puts '*** Please set the LAUNCHDARKLY_SDK_KEY env first'
  exit 1
end

if openai_api_key.nil? || openai_api_key.empty?
  puts '*** Please set the OPENAI_API_KEY env first'
  exit 1
end

#
# Chatbot class that interacts with LaunchDarkly AI and OpenAI
#
class Chatbot
  attr_reader :ai_config, :openai_client, :messages

  def initialize(ai_config, openai_client)
    @ai_config = ai_config
    @messages = ai_config.messages
    @openai_client = openai_client
  end

  def ask_agent(question)
    @messages << LaunchDarkly::Server::AI::Message.new('user', question)
    begin
      completion = ai_config.tracker.track_openai_metrics do
        @openai_client.chat.completions.create(
          model: ai_config.model.name,
          messages: @messages.map(&:to_h)
        )
      end
      response_content = completion[:choices][0][:message][:content]
      @messages << LaunchDarkly::Server::AI::Message.new('assistant', response_content)
      response_content
    rescue StandardError => e
      "An error occurred: #{e.message}"
    end
  end

  def agent_was_helpful(helpful)
    kind = helpful ? :positive : :negative
    ai_config.tracker.track_feedback(kind: kind)
  end
end

DEFAULT_VALUE = LaunchDarkly::Server::AI::AIConfig.new(
  enabled: true,
  model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'replace-with-your-model'),
  messages: [
    LaunchDarkly::Server::AI::Message.new('system',
      'You are the backup assistant when something prevents retrieving LaunchDarkly configured assistant. You have the persona of HAL 9000 talking with {{ldctx.name}}'),
  ]
)

# You can also default to disabled if you are unable to connect to LaunchDarkly services.
# DEFAULT_VALUE = LaunchDarkly::Server::AI::AIConfig.new(
#   enabled: false
# )

ld_client = LaunchDarkly::LDClient.new(sdk_key)
ai_client = LaunchDarkly::Server::AI::Client.new(ld_client)

unless ld_client.initialized?
  puts '*** SDK failed to initialize!'
  exit 1
end

puts '*** SDK successfully initialized'

# Create the LDContext
context = LaunchDarkly::LDContext.create({
                                            key: 'user-key',
                                            kind: 'user',
                                            name: 'Lucy',
                                          })

ai_config = ai_client.config(
  ai_config_key,
  context,
  DEFAULT_VALUE
)

unless ai_config.enabled
  puts '*** AI features are disabled'
  exit 1
end

chatbot = Chatbot.new(ai_config, OpenAI::Client.new(api_key: openai_api_key))

loop do
  print "Ask a question (or type 'exit'): "
  question = gets&.chomp
  break if question.nil? || question.strip.downcase == 'exit'

  response = chatbot.ask_agent(question)
  puts "AI Response: #{response}"
end

print "Was the chat helpful? [yes/no]: "
feedback = gets&.chomp

chatbot.agent_was_helpful(feedback == 'yes') unless feedback.nil?

ld_client.close

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
  attr_reader :aiclient, :ai_config_key, :openai_client, :context

  DEFAULT_VALUE = LaunchDarkly::Server::AI::AIConfig.new(
    enabled: true,
    model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'my-default-model'),
    messages: [
      LaunchDarkly::Server::AI::Message.new('system',
                                      'You are a default unhelpful assistant with the persona of HAL 9000 talking with {{ldctx.name}}'),
      LaunchDarkly::Server::AI::Message.new('user', '{{user_question}}'),
    ]
  )

  def initialize(aiclient, ai_config_key, openai_client, context)
    @aiclient = aiclient
    @ai_config_key = ai_config_key
    @openai_client = openai_client
    @context = context
  end

  def ask_agent(question)
    ai_config = aiclient.config(
      @ai_config_key,
      @context,
      DEFAULT_VALUE,
      { user_question: question }
    )

    begin
      completion = ai_config.tracker.track_openai_metrics do
        @openai_client.chat.completions.create(
          model: ai_config.model.name,
          messages: ai_config.messages.map(&:to_h)
        )
      end
      [completion[:choices][0][:message][:content], ai_config.tracker]
    rescue StandardError => e
      ["An error occurred: #{e.message}", nil]
    end
  end

  def agent_was_helpful(tracker, helpful)
    kind = helpful ? :positive : :negative
    tracker.track_feedback(kind: kind)
  end
end

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

chatbot = Chatbot.new(ai_client, ai_config_key, OpenAI::Client.new(api_key: openai_api_key), context)

loop do
  print "Ask a question (or type 'exit'): "
  input = gets&.chomp
  break if input.nil? || input.strip.downcase == 'exit'

  response, tracker = chatbot.ask_agent(input)
  puts "AI Response: #{response}"

  next if tracker.nil? # If tracker is nil, skip feedback collection

  print "Was the response helpful? [yes/no] (or type 'exit'): "
  feedback = gets&.chomp
  break if feedback.nil? || feedback.strip.downcase == 'exit'

  helpful = feedback.strip.downcase == 'yes'
  chatbot.agent_was_helpful(tracker, helpful)
end

ld_client.close
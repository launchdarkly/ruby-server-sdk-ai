# frozen_string_literal: true

require 'aws-sdk-bedrockruntime'
require 'launchdarkly-server-sdk'
require 'launchdarkly-server-sdk-ai'

# Set sdk_key to your LaunchDarkly SDK key.
sdk_key = ENV['LAUNCHDARKLY_SDK_KEY']

# Set key to the AI Config key you want to evaluate.
ai_config_key = ENV['LAUNCHDARKLY_AI_CONFIG_KEY'] || 'sample-ai-config'

region = ENV['AWS_REGION'] || 'us-east-1'

if sdk_key.nil? || sdk_key.empty?
  puts '*** Please set the LAUNCHDARKLY_SDK_KEY env first'
  exit 1
end

#
# Chatbot class that interacts with LaunchDarkly AI and AWS Bedrock
#
class BedrockChatbot
  attr_reader :ai_config, :bedrock_client, :messages

  def initialize(ai_config, bedrock_client)
    @ai_config = ai_config
    @messages = ai_config.messages
    @bedrock_client = bedrock_client
  end

  # Returns [response_content, resumption_token]. The resumption token can be
  # used to reconstruct a tracker for deferred operations like feedback.
  def ask_agent(question)
    @messages << LaunchDarkly::Server::AI::Message.new('user', question)
    tracker = @ai_config.create_tracker
    begin
      response = tracker.track_bedrock_converse_metrics do
        @bedrock_client.converse(
          map_converse_arguments(
            ai_config.model.name,
            ai_config.messages
          )
        )
      end
      @messages << LaunchDarkly::Server::AI::Message.new('assistant', response.output.message.content[0].text)
      [response.output.message.content[0].text, tracker.resumption_token]
    rescue StandardError => e
      ["An error occured: #{e.message}", nil]
    end
  end

  def agent_was_helpful(helpful, tracker)
    return if tracker.nil?

    kind = helpful ? :positive : :negative
    tracker.track_feedback(kind: kind)
  end

  def map_converse_arguments(model_id, messages)
    args = {
      model_id: model_id,
    }

    chat_messages = messages.select { |msg| msg.role != 'system' }
    args[:messages] = chat_messages.map { |msg| { role: msg.role, content: [{ text: msg.content }] } }

    system_messages = messages.select { |msg| msg.role == 'system' }
    args[:system] = system_messages.map { |msg| { text: msg.content } } unless system_messages.empty?

    args
  end
end

# Initialize the LaunchDarkly client
ld_client = LaunchDarkly::LDClient.new(sdk_key)
ai_client = LaunchDarkly::Server::AI::Client.new(ld_client)

unless ld_client.initialized?
  puts '*** SDK failed to initialize!'
  exit 1
end

# Create the LDContext
context = LaunchDarkly::LDContext.create({
                                           key: 'user-key',
                                           kind: 'user',
                                           name: 'Lucy',
                                         })

bedrock_client = Aws::BedrockRuntime::Client.new(
  region: region
)

# Pass a default for improved resiliency when the flag is unavailable or LaunchDarkly is unreachable; omit for a disabled default.
# Example:
#   default = LaunchDarkly::Server::AI::AIConfig.new(
#     enabled: true,
#     model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'my-model'),
#     provider: LaunchDarkly::Server::AI::ProviderConfig.new(name: 'my-provider'),
#     messages: [LaunchDarkly::Server::AI::Message.new('system', 'Fallback system prompt')]
#   )
#   ai_config = ai_client.completion_config(key: ai_config_key, context:, default:)
ai_config = ai_client.completion_config(key: ai_config_key, context:)

unless ai_config.enabled
  puts '*** AI features are disabled'
  exit 1
end

chatbot = BedrockChatbot.new(ai_config, bedrock_client)

last_resumption_token = nil

loop do
  print "Ask a question (or type 'exit'): "
  question = gets&.chomp
  break if question.nil? || question.strip.downcase == 'exit'

  response, last_resumption_token = chatbot.ask_agent(question)
  puts "AI Response: #{response}"
end

print "Was the chat helpful? [yes/no]: "
feedback = gets&.chomp

unless feedback.nil? || last_resumption_token.nil?
  tracker = LaunchDarkly::Server::AI::AIConfigTracker.from_resumption_token(
    token: last_resumption_token,
    ld_client:,
    context:
  )
  chatbot.agent_was_helpful(feedback == 'yes', tracker)
end

ld_client.close

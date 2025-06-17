# frozen_string_literal: true

require 'aws-sdk-bedrockruntime'
require 'launchdarkly-server-sdk'
require 'launchdarkly-server-sdk-ai'

# Set sdk_key to your LaunchDarkly SDK key.
sdk_key = ENV['LAUNCHDARKLY_SDK_KEY']

# Set config_key to the AI Config key you want to evaluate.
ai_config_key = ENV['LAUNCHDARKLY_AI_CONFIG_KEY'] || 'sample-ai-config'

# Set aws_access_key_id and aws_secret_access_key for AWS credentials.
aws_access_key_id = ENV['AWS_ACCESS_KEY_ID']
aws_secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
region = ENV['AWS_REGION'] || 'us-east-1'

if sdk_key.nil? || sdk_key.empty?
  puts '*** Please set the LAUNCHDARKLY_SDK_KEY env first'
  exit 1
end

if aws_access_key_id.nil? || aws_access_key_id.empty?
  puts '*** Please set the AWS_ACCESS_KEY_ID env variable first'
  exit 1
end

if aws_secret_access_key.nil? || aws_secret_access_key.empty?
  puts '*** Please set the AWS_SECRET_ACCESS_KEY env variable first'
  exit 1
end

#
# Chatbot class that interacts with LaunchDarkly AI and AWS Bedrock
#
class BedrockChatbot
  attr_reader :aiclient, :ai_config_key, :bedrock_client

  DEFAULT_VALUE = LaunchDarkly::Server::AI::AIConfig.new(
    enabled: true,
    model: LaunchDarkly::Server::AI::ModelConfig.new(name: 'my-default-model'),
    messages: [
      LaunchDarkly::Server::AI::Message.new('system',
                                            'You are a default unhelpful assistant with the persona of HAL 9000 talking with {{ldctx.name}}'),
      LaunchDarkly::Server::AI::Message.new('user', '{{user_question}}'),
    ]
  )

  def initialize(aiclient, ai_config_key, bedrock_client, context)
    @aiclient = aiclient
    @ai_config_key = ai_config_key
    @bedrock_client = bedrock_client
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
      response = ai_config.tracker.track_bedrock_converse_metrics do
        @bedrock_client.converse(
          map_converse_arguments(
            ai_config.model.name,
            ai_config.messages
          )
        )
      end
      [response.output.message.content[0].text, ai_config.tracker]
    rescue StandardError => e
      ["An error occured: #{e.message}", nil]
    end
  end

  def agent_was_helpful(tracker, helpful)
    kind = helpful ? :positive : :negative
    tracker.track_feedback(kind: kind)
  end

  def map_converse_arguments(model_id, messages)
    args = {
      model_id: model_id,
    }

    mapped_messages = []
    user_messages = messages.select { |msg| msg.role == 'user' }
    mapped_messages << { role: 'user', content: user_messages.map { |msg| { text: msg.content } } } unless user_messages.empty?

    assistant_messages = messages.select { |msg| msg.role == 'assistant' }
    mapped_messages << { role: 'assistant', content: assistant_messages.map { |msg| { text: msg.content } } } unless assistant_messages.empty?
    args[:messages] = mapped_messages unless mapped_messages.empty?

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
  aws_access_key_id: aws_access_key_id,
  aws_secret_access_key: aws_secret_access_key,
  region: region
)
chatbot = BedrockChatbot.new(ai_client, ai_config_key, bedrock_client, context)

loop do
  print "Ask a question: (or type 'exit'): "
  question = gets&.chomp
  break if question.nil? || question.strip.downcase == 'exit'

  response, tracker = chatbot.ask_agent(question)
  puts "AI Response: #{response}"

  next if tracker.nil? # If tracker is nil, skip feedback collection

  print "Was the response helpful? [yes/no] (or type 'exit'): "
  feedback = gets&.chomp
  break if feedback.nil? || feedback.strip.downcase == 'exit'

  chatbot.agent_was_helpful(tracker, feedback == 'yes')
end

ld_client.close
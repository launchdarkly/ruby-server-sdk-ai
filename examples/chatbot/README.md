# LaunchDarkly sample Ruby AI application

We've built a simple console application that demonstrates how LaunchDarkly's Ruby AI SDK works.

Below, you'll find the build procedure. For more comprehensive instructions, you can visit your [Quickstart page](https://docs.launchdarkly.com/home/ai-configs/quickstart) or the [Ruby reference guide](https://docs.launchdarkly.com/sdk/ai/ruby).

This demo requires Ruby 3.0 or higher.

## Build Instructions

This repository includes examples for `OpenAI` and `Bedrock`. Depending on your preferred provider, you may have to take some additional steps.

### General setup

1. Install the required dependencies with `bundle install` in the appropriate example directory.
1. [Create an AI Config](https://launchdarkly.com/docs/home/ai-configs/create) using the key specified in the examples, or copy the key of an existing AI Config in your LaunchDarkly project that you want to use.
1. Set the environment variable `LAUNCHDARKLY_SDK_KEY` to your LaunchDarkly SDK key and `LAUNCHDARKLY_AI_CONFIG_KEY` to the AI Config key; otherwise, an AI Config of `sample-ai-config` will be assumed.

   ```bash
   export LAUNCHDARKLY_SDK_KEY="1234567890abcdef"
   export LAUNCHDARKLY_AI_CONFIG_KEY="sample-ai-config"
   ```

### OpenAI setup

1. Set the environment variable `OPENAI_API_KEY` to your OpenAI key.

   ```bash
   export OPENAI_API_KEY="0987654321fedcba"
   ```

1. Run the program `bundle exec ruby hello_openai.rb`

### Bedrock setup

1. Ensure the required AWS credentials can be [auto-detected by the AWS client][aws-configuration]. In the provided example we use the following environment variables.

   ```bash
   export AWS_ACCESS_KEY_ID="0987654321fedcba"
   export AWS_SECRET_ACCESS_KEY="0987654321fedcba"

   # or

   export AWS_PROFILE="aws-profile-name"
   ```

1. Run the program `bundle exec ruby hello_bedrock.rb`

[aws-configuration]: https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/configuring.html#precedence-settings
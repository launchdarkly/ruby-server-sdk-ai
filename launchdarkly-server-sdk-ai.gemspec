# frozen_string_literal: true

require_relative 'lib/server/ai/version'

Gem::Specification.new do |spec|
  spec.name = 'launchdarkly-server-sdk-ai'
  spec.version = LaunchDarkly::Server::AI::VERSION
  spec.authors = ['LaunchDarkly']
  spec.email = ['team@launchdarkly.com']
  spec.summary = 'LaunchDarkly AI SDK for Ruby'
  spec.description = 'LaunchDarkly SDK AI Configs integration for the Ruby server side SDK'
  spec.license = 'Apache-2.0'
  spec.homepage = 'https://github.com/launchdarkly/ruby-server-sdk-ai'
  spec.metadata['source_code_uri'] = 'https://github.com/launchdarkly/ruby-server-sdk-ai'
  spec.metadata['changelog_uri'] = 'https://github.com/launchdarkly/ruby-server-sdk-ai/blob/main/CHANGELOG.md'

  spec.files = Dir['{lib}/**/*.rb', 'bin/*', 'LICENSE', '*.md']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.0.0'

  spec.add_dependency 'launchdarkly-server-sdk', '~> 8.5'
  spec.add_dependency 'logger'
  spec.add_dependency 'mustache', '~> 1.1'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'debug', '~> 1.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'rubocop-performance', '~> 1.15'
  spec.add_development_dependency 'rubocop-rake', '~> 0.6'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.0'
end

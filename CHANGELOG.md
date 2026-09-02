# Changelog

## [0.5.0](https://github.com/launchdarkly/ruby-server-sdk-ai/compare/0.4.0...0.5.0) (2026-09-02)


### Features

* **server-ai:** stamp modelKey and modelVersion on AI usage events (AIC-2857) ([#36](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/36)) ([2f7fda4](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/2f7fda4d57b09483cf15fda6e3102e24b1eecb27))


## [0.4.0](https://github.com/launchdarkly/ruby-server-sdk-ai/compare/0.3.0...0.4.0) (2026-05-15)


### ⚠ BREAKING CHANGES

* Replace tracker tuple from completion_config with AIConfig#create_tracker factory
* Track each AIConfigTracker metric at most once per tracker
* Add per-execution runId, at-most-once tracking, and cross-process tracker resumption

### Features

* Add Client#create_tracker(token:, context:) to resume a tracker across processes ([20f06f1](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/20f06f1f24a42692953ae44cebea70aaa416b29d))
* Add per-execution runId to correlate AIConfigTracker events ([20f06f1](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/20f06f1f24a42692953ae44cebea70aaa416b29d))
* Add per-execution runId, at-most-once tracking, and cross-process tracker resumption ([20f06f1](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/20f06f1f24a42692953ae44cebea70aaa416b29d))
* Replace tracker tuple from completion_config with AIConfig#create_tracker factory ([20f06f1](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/20f06f1f24a42692953ae44cebea70aaa416b29d))
* Track each AIConfigTracker metric at most once per tracker ([20f06f1](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/20f06f1f24a42692953ae44cebea70aaa416b29d))

## [0.3.0](https://github.com/launchdarkly/ruby-server-sdk-ai/compare/0.2.2...0.3.0) (2026-03-05)


### ⚠ BREAKING CHANGES

* Use kwargs for completion_config and config methods
* Return disabled config if no defaultValue is provided ([#23](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/23))

### Features

* Drop support for Ruby 3.0 which is EOL. ([fe3fdf8](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/fe3fdf8c022dd4e53e43e9311d76e3b5a098af75))
* Use kwargs for completion_config and config methods ([fe3fdf8](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/fe3fdf8c022dd4e53e43e9311d76e3b5a098af75))


### Bug Fixes

* Return disabled config if no defaultValue is provided ([#23](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/23)) ([fe3fdf8](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/fe3fdf8c022dd4e53e43e9311d76e3b5a098af75))

## [0.2.2](https://github.com/launchdarkly/ruby-server-sdk-ai/compare/0.2.1...0.2.2) (2026-02-25)


### Bug Fixes

* Deprecated config method, use completion_config ([#18](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/18)) ([9f7ec17](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/9f7ec178a87e0f1139c4445d4236cb5db296b0fa))
* Improve usage reporting ([#18](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/18)) ([9f7ec17](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/9f7ec178a87e0f1139c4445d4236cb5db296b0fa))
* Remove bundler version constraint from gemspec ([#20](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/20)) ([ef18f32](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/ef18f323d604b3b4d3ca8f913b66316def34042b))

## [0.2.1](https://github.com/launchdarkly/ruby-server-sdk-ai/compare/0.2.0...0.2.1) (2025-08-28)


### Bug Fixes

* Add usage tracking to config method ([#15](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/15)) ([53ec5f6](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/53ec5f6ea03a160a95baf368355bc90b7383dd64))

## [0.2.0](https://github.com/launchdarkly/ruby-server-sdk-ai/compare/0.1.0...0.2.0) (2025-07-30)


### Features

* added provider and model to ai tracker ([5922fe9](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/5922fe931ad227caa187b46153e8cee77b978032))
* Update AI tracker to include model & provider name for metrics generation ([#11](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/11)) ([ce176e4](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/ce176e42c311857fd6fda30864b8b7cc7b402c20))


### Bug Fixes

* Remove deprecated track generation event ([#10](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/10)) ([dc13cfb](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/dc13cfb0121e613ccbbfe8f9fda8868b9590e356))
* Remove unused instance variable ([#13](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/13)) ([6a04b8b](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/6a04b8ba6c85922856e3236d3d31393cd9d17180))

## [0.1.0](https://github.com/launchdarkly/ruby-server-sdk-ai/compare/0.0.0...0.1.0) (2025-06-18)


### Features

* Implement the AIClient and AITracker classes ([#1](https://github.com/launchdarkly/ruby-server-sdk-ai/issues/1)) ([7511fe9](https://github.com/launchdarkly/ruby-server-sdk-ai/commit/7511fe96e7eb9cec2140d0292fe251c2fb161840))

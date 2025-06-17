## Verifying SDK build provenance with the SLSA framework

LaunchDarkly uses the [SLSA framework](https://slsa.dev/spec/v1.0/about) (Supply-chain Levels for Software Artifacts) to help developers make their supply chain more secure by ensuring the authenticity and build integrity of our published SDK packages.

As part of [SLSA requirements for level 3 compliance](https://slsa.dev/spec/v1.0/requirements), LaunchDarkly publishes provenance about our SDK package builds using [GitHub's generic SLSA3 provenance generator](https://github.com/slsa-framework/slsa-github-generator/blob/main/internal/builders/generic/README.md#generation-of-slsa3-provenance-for-arbitrary-projects) for distribution alongside our packages. These attestations are available for download from the GitHub release page for the release version under Assets > `multiple-provenance.intoto.jsonl`.

To verify SLSA provenance attestations, we recommend using [slsa-verifier](https://github.com/slsa-framework/slsa-verifier). Example usage for verifying SDK packages is included below:

<!-- x-release-please-start-version -->
```
# Set the version of the SDK to verify
VERSION=0.0.0
```
<!-- x-release-please-end -->

```
# Download gem
$ gem fetch launchdarkly-server-sdk-ai -v $VERSION

# Download provenance from Github release
$ curl --location -O \
  https://github.com/launchdarkly/ruby-server-sdk-ai/releases/download/${VERSION}/launchdarkly-server-sdk-ai-${VERSION}.gem.intoto.jsonl

# Run slsa-verifier to verify provenance against package artifacts 
$ slsa-verifier verify-artifact \
--provenance-path launchdarkly-server-sdk-ai-${VERSION}.gem.intoto.jsonl \
--source-uri github.com/launchdarkly/ruby-server-sdk-ai \
launchdarkly-server-sdk-ai-${VERSION}.gem
```

Below is a sample of expected output.
TODO: Verify these are accurate
```
Verified signature against tlog entry index 83653185 at URL: https://rekor.sigstore.dev/api/v1/log/entries/24296fb24b8ad77a7df0bbf87a7d5fcaafa551a2101d9f993d251a56a918bb113e81d2c575dc7e25
Verified build using builder "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@refs/tags/v1.10.0" at commit 14c48a68c45871c27409591969e7f4c0ebdcdf62
Verifying artifact launchdarkly-server-sdk-ai-1.0.0.gem: PASSED

PASSED: Verified SLSA provenance
```

Alternatively, to verify the provenance manually, the SLSA framework specifies [recommendations for verifying build artifacts](https://slsa.dev/spec/v1.0/verifying-artifacts) in their documentation.

**Note:** These instructions do not apply when building our libraries from source. 

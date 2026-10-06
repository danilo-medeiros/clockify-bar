# Publishing a release

The `Release` GitHub Actions workflow tests the app on Apple Silicon and Intel runners, builds a universal macOS app, verifies its signature and architectures, then publishes a ZIP and SHA-256 checksum to GitHub Releases. No Clockify account, API key, or manually configured GitHub token is needed for the build.

## Publish a version

After changes have been committed and pushed to `main`:

```sh
git tag -a v1.0.1 -m "Clockify Bar 1.0.1"
git push origin v1.0.1
```

Use an unused tag in the exact format `vMAJOR.MINOR.PATCH`. The tag determines both the app version and the asset name; `Resources/Info.plist` is a development template. Check the **Actions → Release** run, then verify both assets on the new release page. The workflow waits for tests on both architectures before publishing.

Release permissions come from GitHub’s built-in `GITHUB_TOKEN`, scoped to this repository. Actions must be enabled, and repository/organization policies must allow the release job to write repository contents. No personal token should be added to source files or workflow settings.

Do not move a tag or replace a published binary silently. Publish a new patch version for fixes. A failed run before publication can be rerun from Actions. If publication was partially completed, inspect the existing release before retrying; the workflow does not overwrite releases automatically.

## Build release assets locally

```sh
swift test
bash scripts/package-release.sh 1.0.1
```

Outputs:

```text
dist/releases/v1.0.1/
  Clockify-Bar-1.0.1-macOS-universal.zip
  SHA256SUMS.txt
```

Both architectures are built from the same source using Swift’s `--arch arm64 --arch x86_64` options. The release scripts require macOS and Xcode/Swift tools.

## Signing

Current releases use an ad-hoc code signature. They are not Developer ID signed or notarized, so downloaded copies may require the per-app **Open Anyway** approval documented in the installation guide. No global security settings need to be disabled.

To remove that first-launch warning in a future release, configure an Apple Developer ID Application certificate and notarization credentials, then add hardened-runtime signing, notarization, and stapling before the archive step. Keep signing credentials in GitHub Actions secrets, never in the repository. No such credentials are currently required or configured by these workflows.

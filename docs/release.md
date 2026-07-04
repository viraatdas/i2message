# Release Pipeline

i2Message ships as a direct-distributed macOS DMG. The release pipeline builds a Developer ID signed app, validates hardened runtime and entitlements, notarizes and staples the app, packages a DMG, notarizes and staples the DMG, generates SHA-256 checksums, and uploads the DMG plus checksum file to GitHub Releases.

No Apple credentials, certificates, app-specific passwords, API keys, or generated keychains belong in the repository.

## Local Unsigned Dry Run

Use this before configuring private release credentials:

```sh
./scripts/release/local-dry-run.sh
```

The dry run builds a Release app with code signing disabled, validates the app bundle structure, creates `build/Release/i2Message-<version>-unsigned.dmg`, mounts the DMG to verify that `i2Message.app` and the `/Applications` symlink are present, and writes `build/Release/SHA256SUMS.txt`.

The dry run intentionally skips Developer ID signing, notarization, stapling, and Gatekeeper assessment.

## Required GitHub Secrets

Add these in GitHub: Settings -> Secrets and variables -> Actions -> Repository secrets.

Required for signed releases:

- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`: Base64-encoded `.p12` export containing the Developer ID Application certificate and private key.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`: Password for the exported `.p12`.
- `KEYCHAIN_PASSWORD`: Temporary CI keychain password.

Preferred notarization credentials:

- `APP_STORE_CONNECT_KEY_ID`: App Store Connect API key ID.
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect issuer ID.
- `APP_STORE_CONNECT_API_KEY_P8`: Contents of the `.p8` private key. Literal newlines or escaped `\n` are both accepted.

Fallback notarization credentials:

- `APPLE_ID`: Apple ID email address.
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for notarization.

The release workflow uses the standard GitHub Actions token for Release creation. The workflow grants `contents: write`, so no custom `GITHUB_TOKEN` secret is required.

## Creating The Certificate Secret

Export a Developer ID Application certificate from Keychain Access as a password-protected `.p12`, then encode it:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste the copied value into `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`. Keep the `.p12` file out of the repository.

## Cutting A Release

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `App/i2Message.xcconfig` if needed.
2. Verify locally:

   ```sh
   ./scripts/verify.sh
   ./scripts/release/local-dry-run.sh
   ```

3. Push a version tag:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

On `v*` tags, `.github/workflows/release.yml` runs tests, imports the Developer ID certificate into a temporary keychain, archives and exports the app, notarizes with App Store Connect API key credentials when present, staples, packages a signed DMG, notarizes and staples the DMG, generates checksums, uploads workflow artifacts, and creates or updates the GitHub Release.

## Manual CI Dry Run

Use the `Release` workflow's `workflow_dispatch` trigger with `dry_run=true`. This runs the same unsigned dry-run path as local packaging and uploads the unsigned DMG as a workflow artifact. It does not require Apple secrets and does not create a GitHub Release.

## Validation Performed

The release scripts validate:

- Required tools are installed: `xcodebuild`, `xcrun`, `xcodegen`, `hdiutil`, `codesign`, `shasum`, and signing tools in production mode.
- Release secrets are present before production signing starts.
- The exported app contains a valid `Contents/Info.plist`, executable, bundle identifier, and executable name.
- Signed release apps pass `codesign --verify --deep --strict`.
- Hardened runtime is enabled on signed release apps.
- The signed app includes `com.apple.security.automation.apple-events`.
- DMGs mount successfully and preserve the expected root structure: `i2Message.app` plus `/Applications`.
- Stapling is validated with `xcrun stapler validate`.
- Gatekeeper assessment runs with `spctl` for apps and DMGs where available.

## Script Entry Points

- `scripts/release/local-dry-run.sh`: unsigned local or manual CI packaging.
- `scripts/release/ci-release.sh`: full CI release orchestration.
- `scripts/release/build-archive.sh`: Developer ID archive and export.
- `scripts/release/package-dmg.sh`: DMG construction and structure validation.
- `scripts/release/notarize.sh`: App Store Connect API key notarization with Apple ID fallback.
- `scripts/release/staple-and-assess.sh`: stapling, stapler validation, and Gatekeeper assessment.
- `scripts/release/checksums.sh`: SHA-256 checksum generation.

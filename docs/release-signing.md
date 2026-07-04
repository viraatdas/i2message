# Release And Signing

i2Message uses direct Developer ID distribution. The full operational runbook is in `docs/release.md`; this document captures the signing assumptions that affect app architecture.

## Distribution Model

The app is intentionally non-sandboxed because read-only Messages history access requires user-granted Full Disk Access to private user storage that is not available inside a normal Mac App Store sandbox.

Debug builds and tests disable code signing in scripts so a fresh checkout can verify without Apple Developer credentials. Production releases require a Developer ID Application certificate, hardened runtime, notarization, stapling, and Gatekeeper assessment.

## Required User Permissions

- Full Disk Access: required for read-only access to `~/Library/Messages/chat.db` and related attachment paths.
- Contacts: optional, used to resolve names and avatars.
- Apple Events: required for supported Messages.app automation flows.
- Notifications: optional, used for new-message alerts.

Full Disk Access is a TCC grant, not an entitlement. The app must guide the user to System Settings when real Messages data access is enabled.

## Data Mutation Rule

Do not write directly to `chat.db`, WAL files, attachment directories, or any private Messages database. Use read-only SQLite connections for reads, and supported automation APIs for mutations where macOS permits them.

## Hardened Runtime And Entitlements

`ENABLE_HARDENED_RUNTIME = YES` is enabled in project settings. Release validation fails if the signed app is missing the hardened runtime flag.

The entitlement file currently contains:

- `com.apple.security.automation.apple-events`

Add additional hardened runtime exceptions only with a documented reason and a test that proves the feature requires it.

## Release Entry Points

Unsigned local packaging:

```sh
./scripts/release/local-dry-run.sh
```

Full CI release orchestration:

```sh
./scripts/release/ci-release.sh
```

Tag-triggered GitHub Releases are handled by `.github/workflows/release.yml`.

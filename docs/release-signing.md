# Release And Signing

i2Message is prepared for direct-distributed, notarized macOS builds. The app is intentionally non-sandboxed because Messages history access requires user-granted Full Disk Access to private user storage that is not available inside a normal Mac App Store sandbox.

## Debug Builds

Debug builds use automatic signing and the placeholder bundle identifier `dev.viraat.i2message`.

Set `DEVELOPMENT_TEAM` in `App/i2Message.xcconfig` locally or through Xcode if you want signed local launches outside Xcode.

## Required User Permissions

- Full Disk Access: required for read-only access to `~/Library/Messages/chat.db` and related attachment paths.
- Contacts: optional, used to resolve names and avatars.
- Apple Events: required only for supported automation flows such as future send operations through Messages.app.
- Notifications: optional, used for new-message alerts.

Full Disk Access is a TCC grant, not an entitlement. The app must guide the user to System Settings when real Messages data access is enabled.

## Data Mutation Rule

Do not write directly to `chat.db`, WAL files, attachment directories, or any private Messages database. Use read-only SQLite connections for reads, and supported automation APIs for mutations where macOS permits them.

## Hardened Runtime

`ENABLE_HARDENED_RUNTIME = YES` is enabled in project settings. The entitlement file currently contains only:

- `com.apple.security.automation.apple-events`

Add additional hardened runtime exceptions only with a documented reason and a test that proves the feature requires it.

## Archive

```sh
./scripts/release/build-archive.sh
```

The archive script expects a configured Developer ID Application identity and writes output under `build/Release`.

## Notarization Template

```sh
NOTARY_PROFILE=i2message-notary ./scripts/release/notarize-template.sh build/Release/i2Message.zip
```

Create the notary keychain profile locally with `xcrun notarytool store-credentials`. Do not commit Apple IDs, passwords, app-specific passwords, issuer IDs, key IDs, private keys, or generated keychain profiles.

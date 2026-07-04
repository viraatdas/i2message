# i2Message Ship Checklist

Date: 2026-07-04

## Current Status

Status: ready for unsigned local QA and credentialed release dry run. The remaining release skips are credential-only: Developer ID signing, notarization, stapling, Gatekeeper assessment of signed artifacts, and GitHub Release upload require the user's real Apple/GitHub repository secrets.

## Verification Results

| Area | Status | Evidence |
| --- | --- | --- |
| Script syntax | PASS | `find scripts -type f -name '*.sh' -exec bash -n {} \;` |
| App plists | PASS | `plutil -lint App/Info.plist App/i2Message.entitlements` |
| Full local verify | PASS | `./scripts/verify.sh` regenerated the project, built Debug, and ran the full test suite. |
| Performance benchmark | PASS | 120 conversations / 12,000 messages: launch 0.1193s, transcript page 0.00023s, exact search 0.0027s, semantic search 0.3496s, transcript route 0.00010s. |
| Unsigned release dry run | PASS | `./scripts/release/local-dry-run.sh` produced `build/Release/i2Message-0.1.0-unsigned.dmg`. |
| Unsigned DMG checksum | PASS | SHA-256 `1ccc474b645e0e8cc76ad5c2bb1d085800c63d10a79822c91654fcb9f3e50d11`. |
| Credentialed release env | CREDENTIALS REQUIRED | `./scripts/release/validate-env.sh --release` fails only for missing Apple Developer/notarization secrets listed below. |
| Privacy/security scan | PASS | No signing keys, tokens, app-specific passwords, or real Messages data were found in tracked source/test areas; fixtures use synthetic data. |

Known local environment warning: Xcode reports CoreSimulator framework 1051.54.0 is older than build version 1051.55.0. This did not block macOS build/test/release dry-run paths.

## QA Pass

| Area | Status | Notes |
| --- | --- | --- |
| Small and large windows | PASS | Static UI review completed. Contacts detail now uses a responsive horizontal/vertical fallback and shared vertical dividers to avoid compressed small-window overflow. |
| Light/dark/system appearance | PASS | Settings expose system/light/dark and the UI uses native macOS materials/colors. |
| Keyboard navigation | PASS | Commands cover compose, settings, conversation up/down, search, semantic search, command palette, and composer send. |
| VoiceOver labels | PASS | Rows, message bubbles, attachments, permission controls, skeletons, and major actions have native or explicit labels. |
| Text overflow | PASS | Long search/contact/conversation text is constrained with line limits and truncation in dense surfaces. |
| Loading/empty/error states | PASS | Skeleton lists, empty states, status banners, and permission fallbacks are wired through the app view model. |
| Reduced motion | PASS | State transitions respect `accessibilityReduceMotion`. |
| Transcript virtualization | PASS | Transcript uses lazy stacks and bounded older-message pagination. |
| Search navigation | PASS | Exact, semantic, and hybrid search have paged results and route back to transcript anchors. |
| Permission onboarding | PASS | Settings and sidebar surfaces expose Full Disk Access, Contacts, Automation, and Notifications states and request actions. |
| Send/reply fallback states | PASS | Direct sends use Messages.app automation only after permission checks; reply/unsupported parity states are explicit. Real account send QA still requires a signed local app and Messages account. |

No automated SwiftUI screenshot harness exists in this repo, so UI QA was completed through static SwiftUI review plus app-model tests rather than recorded screenshots.

## Privacy And Safety

- Production Messages storage is opened read-only with `SQLITE_OPEN_READONLY`, `sqlite3_db_readonly`, and `PRAGMA query_only = ON`.
- Sending and open-in-Messages flows go through safe handoff/Apple Events paths; the app does not mutate `chat.db` to send or mark messages.
- Diagnostics and tests avoid logging or committing real message content. Synthetic fixtures use generated names, numbers, and message bodies.
- `.gitignore` excludes Rudder local context and signing/notarization materials including `*.p8`, `*.p12`, `*.cer`, provisioning profiles, developer profiles, keychains, and notary profiles.

Useful local scans:

```sh
find . \( -path './build' -o -path './.git' -o -path './.jj' -o -path './i2Message.xcodeproj' \) -prune -o \( -name '*.p8' -o -name '*.p12' -o -name '*.cer' -o -name '*.mobileprovision' -o -name '*.provisionprofile' -o -name '*.developerprofile' -o -name '*.keychain-db' -o -name 'notarytool-profile.json' \) -print
rg -n --hidden -g '!build/**' -g '!i2Message.xcodeproj/**' -g '!.git/**' -g '!.jj/**' '(BEGIN [A-Z ]*PRIVATE KEY|APP_STORE_CONNECT_API_KEY_P8[=]|DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64[=]|APPLE_APP_SPECIFIC_PASSWORD[=]|gh[p]_|github_p[a]t_|s[k]-[A-Za-z0-9_-]{20,}|xo[x][baprs]-|A[K]IA[0-9A-Z]{16})'
```

## Known Apple API Parity Limits

These are expected limitations caused by private or unavailable Messages APIs:

- SMS/MMS/RCS direct send is not guaranteed; fallback is Messages.app handoff/automation when allowed.
- Creating arbitrary group conversations is not exposed through a public supported API.
- Anchored replies are not exposed through Messages AppleScript.
- Mark read/unread, tapbacks, edits, undo send, delete, pin, and mute are unsupported without private APIs or direct database mutation.
- Deep-linking to an exact Messages conversation is best-effort through public handoff/open behavior.
- Full Disk Access, Contacts, Automation, Notifications, and real sending must be verified on the user's signed local app/account because TCC and account state cannot be fully automated in CI.

## Local Verification Commands

```sh
./scripts/verify.sh
xcodebuild -project i2Message.xcodeproj -scheme i2Message -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO test -only-testing:i2MessageAppTests/AppIntegrationPerformanceTests/testSyntheticPerformanceBudgets -quiet
./scripts/release/local-dry-run.sh
./scripts/release/validate-env.sh --release
```

`./scripts/release/validate-env.sh --release` should fail locally until the real release secrets are available.

## Credentialed Release Checklist

Required GitHub repository secrets:

- `APPLE_TEAM_ID`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- App Store Connect API path: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`
- Apple ID fallback path: `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`

Release flow:

1. Configure the secrets above in the GitHub repository.
2. Push a `v*` tag to trigger `.github/workflows/release.yml`.
3. Confirm CI signs the app and DMG, notarizes, staples, runs Gatekeeper assessment, writes checksums, and publishes the GitHub Release.
4. Download the published DMG on a clean Mac, verify checksum, open it, drag-install the app, grant Full Disk Access/Contacts/Automation/Notifications, and run real-account read/search/send-handoff QA.

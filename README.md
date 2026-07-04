# i2Message

i2Message is a native SwiftUI macOS client for Messages/iMessage workflows. The app is built for complete Messages.app parity where macOS allows it, with faster loading, paginated browsing, exact search, local semantic search, and a restrained native interface.

This repository starts with mock data only. Feature workers should add real readers, indexers, and automation behind the shared contracts in `Sources/i2MessageCore`.

## Requirements

- macOS 14 or newer
- Xcode 26 or newer
- XcodeGen 2.45 or newer

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

## Generate, Build, Test, Launch

From a fresh checkout:

```sh
./scripts/generate-xcodeproj.sh
./scripts/build.sh
./scripts/test.sh
./scripts/run-mock-app.sh
```

The scripts generate `i2Message.xcodeproj`, build into `build/DerivedData`, run unit tests, and open the mock macOS app.

The debug build and test scripts disable code signing so a fresh checkout can verify without a personal Apple Developer Team. Release/archive scripts keep signing enabled.

To work in Xcode:

```sh
open i2Message.xcodeproj
```

Use the `i2Message` scheme.

## Project Layout

- `project.yml` owns the Xcode project structure, targets, package dependencies, and schemes.
- `App/` contains build settings, Info.plist, and signing/entitlement placeholders.
- `Sources/i2MessageCore/` contains shared domain models and protocol contracts.
- `Sources/i2MessageApp/` contains the SwiftUI mock shell.
- `Resources/` contains app assets.
- `Tests/` contains unit test scaffolding.
- `scripts/` contains generation, build, test, run, and release hooks.
- `docs/release-signing.md` documents direct distribution, hardened runtime, and notarization.

Feature workers should add source files under `Sources/` and tests under `Tests/`. Avoid editing `project.yml` unless a truly new target or dependency is required.

## Dependency Baseline

The XcodeGen manifest declares shared packages up front:

- GRDB for SQLite access and FTS-backed exact search.
- Swift Collections for fast ordered collections, deques, and cache/index data structures.
- Swift Async Algorithms for async streams, debouncing, and indexing pipelines.
- SwiftLog for shared structured logging.

The mock app does not read Messages data and does not import these packages yet. They are present so data, search, and indexing workers can use them without changing project manifests.

## Data Safety Rules

i2Message must never write directly to `~/Library/Messages/chat.db`, its WAL files, attachments, or related private Messages storage. Read access is allowed only through read-only SQLite connections after the user grants Full Disk Access.

Sending, deleting, editing, reacting, marking read, or mutating Messages state must go through supported user-facing automation where possible, such as Apple Events or Shortcuts-style automation. If macOS blocks a parity feature, the implementation should return a typed capability or permission error from `i2MessageCore` instead of attempting unsupported database mutation.

## Privacy Model

- Messages data stays local by default.
- Exact search and semantic search indexes are local-only.
- Semantic snippets must not call external embedding services unless a future explicit opt-in setting and privacy review are added.
- Logs must not contain message bodies, attachment paths, phone numbers, email addresses, or contact names.

## Build And Signing

Debug builds use automatic local signing. Direct distribution requires a Developer ID Application certificate, hardened runtime, notarization credentials, and the non-sandbox entitlement assumptions documented in `docs/release-signing.md`.

No signing secrets, Apple IDs, app-specific passwords, API keys, or notarization profiles should be committed.

## Rudder/JJ Note

This repo uses jj workspaces during Rudder execution. Inspect local changes with `jj status` and `jj diff`; Rudder snapshots and integrates worker output.

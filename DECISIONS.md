# Decisions

Shared, agent-authored log of cross-cutting decisions the fleet must honor. The conductor records plan/steer decisions here; workers record interface contracts + adjustments. Re-read before each significant step.

## Plan approved
- **What:** Approved a 8-task plan for: make a beautiful modern imessage client for my mac that shows messages contacts works really well end to end with better and super fast search and semantic search and just looks good works well isn't as buggy and is built to be extremely fast load and paginates fast searches all that. Tasks: SwiftUI app foundation; Messages and contacts data layer; Fast exact and semantic search; Parity actions and macOS integration; Native SwiftUI client experience; End-to-end integration and performance; DMG signing notarization and GitHub Releases; Final QA polish and release readiness.
- **Why:** user-approved plan; workers implement these nodes in isolated workspaces, honoring the dependency edges
- **By:** conductor · 1783128244908

## n0: Created the SwiftUI macOS foundation: XcodeGen project, signing/notarization sc…
- **Did:** Created the SwiftUI macOS foundation: XcodeGen project, signing/notarization scaffolding, README/docs, mock native app shell, shared i2MessageCore domain contracts, unit tests, scripts, CI placeholder, and verified generate/build/test/open flows.
- **Interfaces:** project.yml targets i2Message/i2MessageCore/i2MessageCoreTests; App/Info.plist, App/i2Message.entitlements, App/i2Message.xcconfig; Sources/i2MessageCore models Contact/Conversation/Message/MessageAttachment/SearchResult/SemanticSnippet/Page/Permission/AppSettings/SendOperation/I2MessageError plus repository/search/permission/settings/sending/read-only database protocols; Sources/i2MessageApp SwiftUI mock shell and MockInboxViewModel; scripts/generate-xcodeproj.sh build.sh test.sh run-mock-app.sh verify.sh release hooks
- **Follow-ups:**
  - Implement real read-only Messages data adapter [out of lane] — Foundation exposes MessagesDatabaseReading and repository contracts, but real chat.db access and permission onboarding are outside this worker lane.
  - Implement exact and semantic search providers [out of lane] — Search contracts and dependency baselines are ready; real FTS and local embedding/index pipelines remain feature work.
  - Add production app icon and signed archive export options [out of lane] — Signing and notarization templates are present, but final brand icon assets and team-specific export settings require owner choices/secrets.
- **By:** n0 · 2026-07-04T01:37:20.602Z

## n1: Resolved inherited `.gitignore` conflict
- **Did:** The n1 workspace contained an unresolved `.gitignore` conflict between Rudder-local ignores and n0's generated Xcode/SPM/signing ignores; resolved it by preserving both sets of rules before implementing data access.
- **Why:** Build/test and `jj` inspection would remain unreliable with conflict markers in a root project file.
- **By:** n1 · 2026-07-04T01:44:00Z

## n1: Implemented read-only Messages and Contacts data layer
- **Did:** Added read-only SQLite-backed Messages repositories, Contacts.framework resolution/cache, Full Disk Access/Contacts permission diagnostics, polling change detection, stable cursor pagination, attachment/tapback/reply mapping, synthetic fixtures, performance smoke tests, and `docs/data-access.md`.
- **Interfaces:** `MessagesDataAccessStack`, `MessagesStoreConfiguration`, `ReadOnlyMessagesStore`, `MessagesStoreDiagnosticService`, `MessagesChangeMonitoring`/`PollingMessagesChangeMonitor`, `SQLiteConversationRepository`, `SQLiteMessageRepository`, `SQLiteAttachmentRepository`, `SystemContactsProvider`, `ContactResolving`, `ContactHandleNormalizer`, `MacOSPermissionManager`.
- **Safety:** SQLite opens use `SQLITE_OPEN_READONLY` plus `PRAGMA query_only = ON`; tests generate temporary synthetic chat.db schemas and do not read or copy real user Messages data.
- **By:** n1 · 2026-07-04T02:08:00Z

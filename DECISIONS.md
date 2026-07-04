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

## n0: Resolved the .gitignore jj merge conflict by preserving both
- **Did:** Resolved the .gitignore jj merge conflict by preserving both the SwiftUI foundation ignore rules and Rudder local-context ignore rules. Verified jj reports no conflicts and ./scripts/test.sh passed.
- **Interfaces:** .gitignore now ignores generated Xcode/SPM/build artifacts, signing/notarization secrets, and Rudder local context files/directories.
- **By:** n0 · 2026-07-04T01:39:16.099Z

## n2: Implemented local privacy-preserving search subsystem: GRDB/SQLite FTS5 exact i…
- **Did:** Implemented `LocalSearchService` behind `SearchProviding`/`SearchIndexing`, backed by a persistent GRDB/SQLite FTS5 exact index and local semantic embedding table. It indexes messages, contacts, conversations, attachment metadata, and reactions; supports ranked snippets, prefix/token normalization, date/contact/service/attachment filters, paginated cursors, typeahead, recent searches, local natural-language filter parsing, hybrid exact+semantic search, transcript navigation targets, chunked cancellable rebuilds, resumable semantic indexing, and local-only embedding fallback with Apple NaturalLanguage when available. Verified with ./scripts/test.sh and ./scripts/build.sh; both succeeded, with non-blocking CoreSimulator out-of-date warnings from Xcode only.
- **Interfaces:** `SearchIndexCorpusProviding`, `SearchIndexCorpus`, `StaticSearchIndexCorpusProvider`, `LocalSearchService`, `LocalSearchFilters`, `HybridSearchQuery`, `SearchSuggestion`, `RecentSearch`, `SearchNavigationTarget`, `LocalSearchIndexState`, `SemanticEmbeddingProviding`, `AutomaticLocalSemanticEmbedder`, `HashingSemanticEmbedder`; files under `Sources/i2MessageCore/Search/**`, `Sources/i2MessageCore/SemanticSearch/**`, `Tests/i2MessageCoreTests/Search/**`, and `docs/search.md`; `LocalSearchService` conforms to `SearchProviding` and `SearchIndexing`.
- **Why:** Data-layer workers can adapt repositories into `SearchIndexCorpusProviding`; UI/integration workers can call the foundation search protocols plus `LocalSearchService` extras without adding remote services or search-specific database reads elsewhere.
- **Follow-ups:**
  - Wire real repositories into SearchIndexCorpusProviding [out of lane] — Search now consumes a corpus boundary; the data layer should adapt real Messages/Contacts repository output into that provider once n1 lands.
  - Integrate search UI with LocalSearchService extras [out of lane] — UI can use foundation search methods plus typeahead, hybridSearch, recentSearches, localIndexState, and navigationTarget for the polished search experience.
- **By:** n2 · 2026-07-04T02:05:22.718Z

## n2: Resolved local `.gitignore` conflict by preserving foundation and Rudder ignores
- **Did:** Replaced conflict markers with the combined ignore set from n0/foundation plus Rudder-local entries: `.DS_Store`, Xcode/SPM/build artifacts, signing/notarization secrets, `.rudder/`, `.rudder-worktrees/`, `RUDDER.md`, and `RUDDER_SHARED.md`.
- **Why:** This workspace still had an unresolved generated `.gitignore` conflict even though n0 was merged; search verification needs a non-conflicted tree. Sibling agents touching `.gitignore` should integrate on top of the same combined entries rather than dropping either side.
- **By:** n2 · 2026-07-04T02:06:00Z

## n3: Implemented safe Messages parity actions and macOS integration
- **Did:** Implemented safe Messages parity actions and macOS integration without direct Messages storage mutation: action/status models, typed errors, AppleScript command builder, safe send/start/reply/open/handoff/mark-read service behavior, macOS Automation/Contacts/Notifications/NSWorkspace/NSPasteboard adapters, UI permission/parity plumbing, parity docs, and CI-safe tests. Verified ./scripts/generate-xcodeproj.sh, ./scripts/test.sh, and ./scripts/build.sh pass; Xcode emits a local CoreSimulator version warning but macOS tests/build succeed.
- **Interfaces:** Sources/i2MessageCore/MessagingActions/*: MessagingActionServicing, MessagingActionAvailabilitySnapshot, MessagingActionKind, MessagingActionError, MessagingActionResult, MessagingActionPolicy, MessagesAppleScriptCommandBuilder, MessagesAutomationControlling, MessagesHandoffControlling, DraftAttachmentInspecting, MessagingNotificationHooking, SafeMessagingActionService. Sources/i2MessageCore/SystemIntegration/*: MacOSMessagesAutomationController, MacOSMessagesHandoffController, MacOSPermissionManager, MacOSNotificationHook, PermissionStateMapper. Sources/i2MessageApp/Integration/AppIntegrationEnvironment.swift wires live integration into MockInboxViewModel; docs/parity.md defines parity matrix/manual QA.
- **Follow-ups:**
  - Run real-device Messages send and attachment QA [out of lane] — Apple Events, TCC prompts, Messages account state, and notarized app behavior cannot be fully exercised in CI.
  - Wire production attachment picker and drag/drop UI [out of lane] — Core supports DraftAttachment validation/sending and paste/drag handoff, but the current mock composer still leaves the attach control disabled.
- **By:** n3 · 2026-07-04T02:06:19.584Z

## n2: Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserving
- **Did:** Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserving Xcode/SPM/signing/Rudder ignores and consolidating the shared n0/n2/n3 decision records; jj reports no conflicts and ./scripts/test.sh passed.
- **Interfaces:** .gitignore; DECISIONS.md
- **By:** n2 · 2026-07-04T02:07:35.767Z

## n1: Implemented the n1 read-only Messages and Contacts data layer:
- **Did:** Implemented the n1 read-only Messages and Contacts data layer: read-only SQLite store, schema diagnostics, conversation/message/attachment repositories, stable cursor pagination, tapback/reply/attachment mapping, Contacts.framework resolver/cache, macOS permission manager, polling change detection, docs, synthetic fixtures, and tests/benchmarks. Verified with ./scripts/test.sh; tests passed. No real user chat.db or personal Messages data was read or added.
- **Interfaces:** MessagesDataAccessStack; MessagesStoreConfiguration; ReadOnlyMessagesStore; MessagesStoreDiagnosticService/MessagesStoreDiagnostics; MessagesChangeMonitoring/PollingMessagesChangeMonitor; SQLiteConversationRepository; SQLiteMessageRepository; SQLiteAttachmentRepository; SystemContactsProvider; ContactResolving/MessageHandle; ContactHandleNormalizer; MacOSPermissionManager; docs/data-access.md; Tests/i2MessageCoreTests/DataAccess synthetic fixtures and benchmarks
- **Follow-ups:**
  - Wire UI/search lanes to MessagesDataAccessStack after merges [out of lane] — This lane exposes the real repositories, but app/search integration belongs to n4/n2/n5 after Rudder merges worker outputs.
  - Tune production benchmark thresholds on target Macs [out of lane] — Synthetic tests prove bounded fetches without real data; hardware-normalized performance budgets should be set during end-to-end QA with representative local fixtures.
- **By:** n1 · 2026-07-04T02:08:28.459Z
## n3: Resolved the DECISIONS.md jj conflict by preserving the shared
- **Did:** Resolved the DECISIONS.md jj conflict by preserving the shared n0/n2/n3/n1 decision history, consolidating duplicate n3 integration notes, and removing a stale .gitignore follow-up now covered by the later n2 resolution. Verified jj has no unresolved conflicts and ./scripts/test.sh passes with only the known local CoreSimulator warning.
- **Interfaces:** DECISIONS.md shared decision log only; no code interfaces changed.
- **Follow-ups:**
  - Run real-device Messages send and attachment QA [out of lane] — Apple Events, TCC prompts, Messages account state, and notarized app behavior cannot be fully exercised in CI.
  - Wire production attachment picker and drag/drop UI [out of lane] — Core supports DraftAttachment validation and handoff, but the composer UI still needs production picker/drop handling.
- **By:** n3 · 2026-07-04T02:09:31.705Z


# Decisions

Shared, agent-authored log of cross-cutting decisions the fleet must honor. The conductor records plan/steer decisions here; workers record interface contracts + adjustments. Re-read before each significant step.

## Plan approved
- **What:** Approved a 8-task plan for: make a beautiful modern imessage client for my mac that shows messages contacts works really well end to end with better and super fast search and semantic search and just looks good works well isn't as buggy and is built to be extremely fast load and paginates fast searches all that. Tasks: SwiftUI app foundation; Messages and contacts data layer; Fast exact and semantic search; Parity actions and macOS integration; Native SwiftUI client experience; End-to-end integration and performance; DMG signing notarization and GitHub Releases; Final QA polish and release readiness.
- **Why:** user-approved plan; workers implement these nodes in isolated workspaces, honoring the dependency edges
- **By:** conductor · 1783128244908

## n0: Created the SwiftUI macOS foundation: XcodeGen project, signing/notarization scaffolding
- **Did:** Created the SwiftUI macOS foundation: XcodeGen project, signing/notarization scaffolding, README/docs, mock native app shell, shared i2MessageCore domain contracts, unit tests, scripts, and CI placeholder.
- **Interfaces:** project.yml targets i2Message/i2MessageCore/i2MessageCoreTests; App/Info.plist, App/i2Message.entitlements, App/i2Message.xcconfig; shared i2MessageCore models and repository/search/permission/settings/sending contracts; scripts/generate-xcodeproj.sh build.sh test.sh run-mock-app.sh verify.sh release hooks.
- **By:** n0 · 2026-07-04T01:37:20.602Z

## n0: Resolved the .gitignore jj merge conflict by preserving both
- **Did:** Resolved the .gitignore jj merge conflict by preserving both the SwiftUI foundation ignore rules and Rudder local-context ignore rules. Verified jj reports no conflicts and ./scripts/test.sh passed.
- **Interfaces:** .gitignore now ignores generated Xcode/SPM/build artifacts, signing/notarization secrets, and Rudder local context files/directories.
- **By:** n0 · 2026-07-04T01:39:16.099Z

## n2: Implemented local privacy-preserving search subsystem
- **Did:** Implemented `LocalSearchService` behind `SearchProviding`/`SearchIndexing`, backed by a persistent GRDB/SQLite FTS5 exact index and local semantic embedding table. It indexes messages, contacts, conversations, attachment metadata, and reactions; supports ranked snippets, prefix/token normalization, date/contact/service/attachment filters, paginated cursors, typeahead, recent searches, local natural-language filter parsing, hybrid exact+semantic search, transcript navigation targets, chunked cancellable rebuilds, resumable semantic indexing, and local-only embedding fallback with Apple NaturalLanguage when available.
- **Interfaces:** `SearchIndexCorpusProviding`, `SearchIndexCorpus`, `StaticSearchIndexCorpusProvider`, `LocalSearchService`, `LocalSearchFilters`, `HybridSearchQuery`, `SearchSuggestion`, `RecentSearch`, `SearchNavigationTarget`, `LocalSearchIndexState`, `SemanticEmbeddingProviding`, `AutomaticLocalSemanticEmbedder`, `HashingSemanticEmbedder`; files under `Sources/i2MessageCore/Search/**`, `Sources/i2MessageCore/SemanticSearch/**`, `Tests/i2MessageCoreTests/Search/**`, and `docs/search.md`; `LocalSearchService` conforms to `SearchProviding` and `SearchIndexing`.
- **By:** n2 · 2026-07-04T02:05:22.718Z

## n2: Resolved local `.gitignore` conflict by preserving foundation and Rudder ignores
- **Did:** Replaced conflict markers with the combined ignore set from n0/foundation plus Rudder-local entries: `.DS_Store`, Xcode/SPM/build artifacts, signing/notarization secrets, `.rudder/`, `.rudder-worktrees/`, `RUDDER.md`, and `RUDDER_SHARED.md`.
- **By:** n2 · 2026-07-04T02:06:00Z

## n3: Implemented safe Messages parity actions and macOS integration
- **Did:** Implemented safe Messages parity actions and macOS integration without direct Messages storage mutation: action/status models, typed errors, AppleScript command builder, safe send/start/reply/open/handoff/mark-read service behavior, macOS Automation/Contacts/Notifications/NSWorkspace/NSPasteboard adapters, UI permission/parity plumbing, parity docs, and CI-safe tests.
- **Interfaces:** Sources/i2MessageCore/MessagingActions/*; Sources/i2MessageCore/SystemIntegration/*; docs/parity.md.
- **Follow-ups:**
  - Run real-device Messages send and attachment QA [out of lane] — Apple Events, TCC prompts, Messages account state, and notarized app behavior cannot be fully exercised in CI.
  - Wire production attachment picker and drag/drop UI [out of lane] — Core supports DraftAttachment validation/sending and paste/drag handoff, but the current mock composer still leaves the attach control disabled.
- **By:** n3 · 2026-07-04T02:06:19.584Z

## n2: Resolved jj merge conflicts in .gitignore and DECISIONS.md
- **Did:** Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserving Xcode/SPM/signing/Rudder ignores and consolidating the shared n0/n2/n3 decision records; jj reports no conflicts and ./scripts/test.sh passed.
- **Interfaces:** .gitignore; DECISIONS.md
- **By:** n2 · 2026-07-04T02:07:35.767Z

## n1: Implemented the n1 read-only Messages and Contacts data layer
- **Did:** Implemented the n1 read-only Messages and Contacts data layer: read-only SQLite store, schema diagnostics, conversation/message/attachment repositories, stable cursor pagination, tapback/reply/attachment mapping, Contacts.framework resolver/cache, macOS permission manager, polling change detection, docs, synthetic fixtures, and tests/benchmarks. No real user chat.db or personal Messages data was read or added.
- **Interfaces:** MessagesDataAccessStack; MessagesStoreConfiguration; ReadOnlyMessagesStore; MessagesStoreDiagnosticService/MessagesStoreDiagnostics; MessagesChangeMonitoring/PollingMessagesChangeMonitor; SQLiteConversationRepository; SQLiteMessageRepository; SQLiteAttachmentRepository; SystemContactsProvider; ContactResolving/MessageHandle; ContactHandleNormalizer; MessagesDataAccessPermissionManager; docs/data-access.md; Tests/i2MessageCoreTests/DataAccess synthetic fixtures and benchmarks.
- **Safety:** SQLite opens use `SQLITE_OPEN_READONLY` plus `PRAGMA query_only = ON`; tests generate temporary synthetic chat.db schemas and do not read or copy real user Messages data.
- **By:** n1 · 2026-07-04T02:08:28.459Z

## n3: Resolved the DECISIONS.md jj conflict
- **Did:** Resolved the DECISIONS.md jj conflict by preserving the shared n0/n2/n3/n1 decision history, consolidating duplicate n3 integration notes, and removing a stale .gitignore follow-up now covered by the later n2 resolution.
- **Interfaces:** DECISIONS.md shared decision log only; no code interfaces changed.
- **By:** n3 · 2026-07-04T02:09:31.705Z

## n1: Resolved permission manager merge collision
- **Did:** Kept n3's app-wide `MacOSPermissionManager` for Automation/Notifications integration and renamed n1's configured chat.db permission checker to `MessagesDataAccessPermissionManager`; updated the data stack and data-access docs to use the renamed type.
- **Interfaces:** `Sources/i2MessageCore/Permissions/MessagesDataAccessPermissionManager.swift`; `MessagesDataAccessStack.permissions`.
- **By:** n1 · 2026-07-04T02:15:00Z

## n4: Delivered polished SwiftUI macOS app shell against mock/foundation protocols
- **Did:** Delivered polished SwiftUI macOS app shell against mock/foundation protocols: native split-view sidebar modes for conversations/contacts/search, lazy paginated transcript with bubbles/tapbacks/attachments, composer with mock attachment/drop/send flow, exact/semantic/hybrid search workspace with paged results and snippets, settings/permissions/indexing/privacy surfaces, command palette, loading/error/empty/offline states, previews, docs, and UI-model tests.
- **Interfaces:** AppDependencies in Sources/i2MessageApp/Features/App wraps ConversationRepository, MessageRepository, ContactProviding, SearchProviding, SearchIndexing, PermissionManaging, SettingsStoring, and MessageSending; production providers can replace mock services without view rewrites. Added i2MessageAppTests target in project.yml and docs/ui.md UI contract.
- **By:** n4 · 2026-07-04T02:11:14.277Z

## n1: Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserved
- **Did:** Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserved combined ignore rules and shared decision history, fixed merged Swift build issue by keeping n3 app-wide MacOSPermissionManager and renaming n1 data-layer checker to MessagesDataAccessPermissionManager, updated stack/docs/decisions, and verified ./scripts/test.sh succeeds.
- **Interfaces:** .gitignore; DECISIONS.md; Sources/i2MessageCore/Permissions/MessagesDataAccessPermissionManager.swift; Sources/i2MessageCore/DataAccess/MessagesDataAccessStack.swift; docs/data-access.md
- **By:** n1 · 2026-07-04T02:12:47.604Z

## n4: Resolved UI merge conflicts by keeping the AppViewModel shell
- **Did:** Resolved conflicts in the root ignore file, shared decisions, and the app UI files by retaining the n4 native SwiftUI `AppViewModel` shell, deleting the obsolete `MockInboxViewModel`, and preserving the shared n1/n2/n3 decision history.
- **Interfaces:** `.gitignore`; `DECISIONS.md`; `Sources/i2MessageApp/Views/ContentView.swift`; `Sources/i2MessageApp/Views/ConversationDetailView.swift`; `Sources/i2MessageApp/Views/SidebarView.swift`; removed `Sources/i2MessageApp/Mock/MockInboxViewModel.swift`.
- **By:** n4 · 2026-07-04T02:20:00Z

## n4: Resolved all jj merge conflicts for n4 by preserving
- **Did:** Resolved all jj merge conflicts for n4 by preserving the native SwiftUI AppViewModel shell, combined ignore/decision history, and deleting the obsolete MockInboxViewModel. jj reports no conflicts. Verified with ./scripts/test.sh and ./scripts/build.sh; both succeeded with only the known local CoreSimulator warning.
- **Interfaces:** .gitignore; DECISIONS.md; Sources/i2MessageApp/Views/ContentView.swift; Sources/i2MessageApp/Views/ConversationDetailView.swift; Sources/i2MessageApp/Views/SidebarView.swift; removed Sources/i2MessageApp/Mock/MockInboxViewModel.swift; AppDependencies remains the UI integration boundary for production data/search/parity providers.
- **By:** n4 · 2026-07-04T02:17:26.126Z

## n2: Confirmed DECISIONS.md merge resolution is clean: the shared log
- **Did:** Confirmed DECISIONS.md merge resolution is clean: the shared log preserves n0/n1/n2/n3 records and consolidated n4 resolution notes; jj reports no unresolved conflicts; ./scripts/test.sh passed. No additional file edits were needed in this resolver turn.
- **Interfaces:** DECISIONS.md shared decision log only; no code interfaces changed in this resolver turn
- **By:** n2 · 2026-07-04T19:00:50.387Z

## n3: Verified the merge resolution for n3
- **Did:** Verified the merge resolution for n3: jj reports no unresolved conflicts, .gitignore preserves the combined Xcode/SPM/signing/Rudder ignore set, DECISIONS.md preserves the shared n0/n1/n2/n3/n4 decision history, and ./scripts/test.sh passed with only the known local CoreSimulator warning.
- **Interfaces:** .gitignore; DECISIONS.md shared decision log; no code interfaces changed by this resolver
- **By:** n3 · 2026-07-04T19:00:57.481Z

## n1: Verified the jj merge conflict resolution for n1/n4
- **Did:** Verified the jj merge conflict resolution for n1/n4: no unresolved conflicts or conflict markers remain; preserved combined .gitignore and DECISIONS.md history, kept the n4 AppViewModel SwiftUI shell, deleted the obsolete MockInboxViewModel, and verified ./scripts/test.sh plus ./scripts/build.sh pass with only the known CoreSimulator warning.
- **Interfaces:** Conflicted paths resolved: .gitignore, DECISIONS.md, Sources/i2MessageApp/Views/ContentView.swift, Sources/i2MessageApp/Views/ConversationDetailView.swift, Sources/i2MessageApp/Views/SidebarView.swift; removed Sources/i2MessageApp/Mock/MockInboxViewModel.swift; AppDependencies remains the production provider handoff boundary.
- **By:** n1 · 2026-07-04T19:01:13.785Z

## n5: Integrated live read-only Messages/Contacts, local exact/semantic search, safe actions
- **Did:** Integrated live read-only Messages/Contacts, local exact/semantic search, safe parity actions, permissions, background indexing, search-result transcript routing, fixture fallback, diagnostics, integration/performance tests, and performance/manual-smoke docs. Resolved inherited merge conflicts and verified with ./scripts/verify.sh.
- **Interfaces:** AppDependencies.live(configuration:fileManager:); AppDependencies.fixture(...); AppDependencies.indexedFixture(...); AppDiagnostics; CompositeAppPermissionManager; RepositorySearchIndexCorpusProvider; UserDefaultsSettingsStore; AppViewModel.actionAvailabilitySnapshot/openSelectedConversationInMessages/loadMessages(... around:); docs/performance.md; Tests/i2MessageAppTests/Integration/AppIntegrationPerformanceTests.swift
- **Follow-ups:**
  - Real-account macOS QA [out of lane] — Full Disk Access, Automation prompts, Messages account state, and real send/handoff behavior require a signed app and local user account with Messages history; CI cannot fully exercise TCC.
  - Very-large-history semantic indexing tuning [out of lane] — The current local vector scan meets the 12k synthetic target; much larger histories may need ANN indexing or stricter corpus chunking.
- **By:** n5 · 2026-07-04T19:17:58.120Z

## n6: Added repeatable DMG, signing, notarization, and GitHub Releases pipeline
- **Did:** Added release scripts for unsigned local dry runs, CI Developer ID certificate import, signed archive/export, app/DMG validation, app and DMG notarization, stapling, Gatekeeper assessment, checksum generation, and tag-triggered GitHub Release upload. Also resolved inherited AppViewModel merge conflicts in this workspace to unblock release verification without reviving MockInboxViewModel.
- **Interfaces:** `.github/workflows/release.yml`; `scripts/release/common.sh`; `scripts/release/validate-env.sh`; `scripts/release/import-developer-id-certificate.sh`; `scripts/release/build-archive.sh`; `scripts/release/local-dry-run.sh`; `scripts/release/ci-release.sh`; `scripts/release/package-dmg.sh`; `scripts/release/notarize.sh`; `scripts/release/staple-and-assess.sh`; `scripts/release/checksums.sh`; `docs/release.md`; `docs/release-signing.md`.
- **Secrets:** `APPLE_TEAM_ID`, `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`, `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`, preferred App Store Connect API key secrets, optional Apple ID fallback secrets, and standard GitHub Actions token for release upload.
- **By:** n6 · 2026-07-04T19:45:00Z

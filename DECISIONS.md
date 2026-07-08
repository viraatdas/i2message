# Decisions

Shared, agent-authored log of cross-cutting decisions the fleet must honor. The conductor records plan/steer decisions here; workers record interface contracts + adjustments. Re-read before each significant step.

## Plan approved
- **What:** Approved a 8-task plan for: make a beautiful modern imessage client for my mac that shows messages contacts works really well end to end with better and super fast search and semantic search and just looks good works well isn't as buggy and is built to be extremely fast load and paginates fast searches all that. Tasks: SwiftUI app foundation; Messages and contacts data layer; Fast exact and semantic search; Parity actions and macOS integration; Native SwiftUI client experience; End-to-end integration and performance; DMG signing notarization and GitHub Releases; Final QA polish and release readiness.
- **Why:** user-approved plan; workers implement these nodes in isolated workspaces, honoring the dependency edges
- **By:** conductor · 1783128244908

## n0: Created the SwiftUI macOS foundation: XcodeGen project, signing/notarization scaffolding
- **Did:** Created the SwiftUI macOS foundation: XcodeGen project, signing/notarization scaffolding, README/docs, mock native app shell, shared i2MessageCore domain contracts, unit tests, scripts, and CI placeholder, and verified generate/build/test/open flows.
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

## n2: Implemented local privacy-preserving search subsystem
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

## n2: Resolved jj merge conflicts in .gitignore and DECISIONS.md
- **Did:** Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserving Xcode/SPM/signing/Rudder ignores and consolidating the shared n0/n2/n3 decision records; jj reports no conflicts and ./scripts/test.sh passed.
- **Interfaces:** .gitignore; DECISIONS.md
- **By:** n2 · 2026-07-04T02:07:35.767Z

## n1: Resolved inherited `.gitignore` conflict
- **Did:** The n1 workspace contained an unresolved `.gitignore` conflict between Rudder-local ignores and n0's generated Xcode/SPM/signing ignores; resolved it by preserving both sets of rules before implementing data access.
- **Why:** Build/test and `jj` inspection would remain unreliable with conflict markers in a root project file.
- **By:** n1 · 2026-07-04T01:44:00Z

## n1: Implemented the n1 read-only Messages and Contacts data layer
- **Did:** Implemented the n1 read-only Messages and Contacts data layer: read-only SQLite store, schema diagnostics, conversation/message/attachment repositories, stable cursor pagination, tapback/reply/attachment mapping, Contacts.framework resolver/cache, macOS permission manager, polling change detection, docs, synthetic fixtures, and tests/benchmarks. Verified with ./scripts/test.sh; tests passed. No real user chat.db or personal Messages data was read or added.
- **Interfaces:** MessagesDataAccessStack; MessagesStoreConfiguration; ReadOnlyMessagesStore; MessagesStoreDiagnosticService/MessagesStoreDiagnostics; MessagesChangeMonitoring/PollingMessagesChangeMonitor; SQLiteConversationRepository; SQLiteMessageRepository; SQLiteAttachmentRepository; SystemContactsProvider; ContactResolving/MessageHandle; ContactHandleNormalizer; MessagesDataAccessPermissionManager; docs/data-access.md; Tests/i2MessageCoreTests/DataAccess synthetic fixtures and benchmarks
- **Safety:** SQLite opens use `SQLITE_OPEN_READONLY` plus `PRAGMA query_only = ON`; tests generate temporary synthetic chat.db schemas and do not read or copy real user Messages data.
- **Follow-ups:**
  - Wire UI/search lanes to MessagesDataAccessStack after merges [out of lane] — This lane exposes the real repositories, but app/search integration belongs to n4/n2/n5 after Rudder merges worker outputs.
  - Tune production benchmark thresholds on target Macs [out of lane] — Synthetic tests prove bounded fetches without real data; hardware-normalized performance budgets should be set during end-to-end QA with representative local fixtures.
- **By:** n1 · 2026-07-04T02:08:28.459Z

## n3: Resolved the DECISIONS.md jj conflict
- **Did:** Resolved the DECISIONS.md jj conflict by preserving the shared n0/n2/n3/n1 decision history, consolidating duplicate n3 integration notes, and removing a stale .gitignore follow-up now covered by the later n2 resolution. Verified jj has no unresolved conflicts and ./scripts/test.sh passes with only the known local CoreSimulator warning.
- **Interfaces:** DECISIONS.md shared decision log only; no code interfaces changed.
- **Follow-ups:**
  - Run real-device Messages send and attachment QA [out of lane] — Apple Events, TCC prompts, Messages account state, and notarized app behavior cannot be fully exercised in CI.
  - Wire production attachment picker and drag/drop UI [out of lane] — Core supports DraftAttachment validation and handoff, but the composer UI still needs production picker/drop handling.
- **By:** n3 · 2026-07-04T02:09:31.705Z

## n1: Resolved permission manager merge collision
- **Did:** Kept n3's app-wide `MacOSPermissionManager` for Automation/Notifications integration and renamed n1's configured chat.db permission checker to `MessagesDataAccessPermissionManager`; updated the data stack and data-access docs to use the renamed type.
- **Why:** Swift modules cannot contain two public `MacOSPermissionManager` declarations or two same-named Swift source files; the data layer still performs read-only Full Disk Access diagnostics against the configured database URL.
- **Interfaces:** `Sources/i2MessageCore/Permissions/MessagesDataAccessPermissionManager.swift`; `MessagesDataAccessStack.permissions` default implementation.
- **By:** n1 · 2026-07-04T02:15:00Z

## n4: Delivered polished SwiftUI macOS app shell against mock/foundation protocols:
- **Did:** Delivered polished SwiftUI macOS app shell against mock/foundation protocols: native split-view sidebar modes for conversations/contacts/search, lazy paginated transcript with bubbles/tapbacks/attachments, composer with mock attachment/drop/send flow, exact/semantic/hybrid search workspace with paged results and snippets, settings/permissions/indexing/privacy surfaces, command palette, loading/error/empty/offline states, previews, docs, and UI-model tests. Resolved inherited .gitignore conflict. Verified XcodeGen, debug build, and ./scripts/test.sh; visual QA note: UI follows DESIGN.md with native macOS hierarchy, restrained accent usage, compact readable controls, no marketing/glass/gradient patterns, and stable small-window split layout.
- **Interfaces:** AppDependencies in Sources/i2MessageApp/Features/App wraps ConversationRepository, MessageRepository, ContactProviding, SearchProviding, SearchIndexing, PermissionManaging, SettingsStoring, and MessageSending; production providers can replace mock services without view rewrites. Added i2MessageAppTests target in project.yml and docs/ui.md UI contract.
- **Follow-ups:**
  - Wire production providers into AppDependencies after n1/n2/n3 merge [out of lane] — This lane intentionally stayed on mock/foundation protocols while data/search/action workers own real implementations.
  - Add real lazy image thumbnails at AttachmentChip boundary [out of lane] — Current UI renders lightweight attachment chips and transfer states; production thumbnails should remain lazy-loaded once attachment preview providers exist.
- **By:** n4 · 2026-07-04T02:11:14.277Z

## n1: Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserved
- **Did:** Resolved jj merge conflicts in .gitignore and DECISIONS.md, preserved combined ignore rules and shared decision history, fixed merged Swift build issue by keeping n3 app-wide MacOSPermissionManager and renaming n1 data-layer checker to MessagesDataAccessPermissionManager, updated stack/docs/decisions, and verified ./scripts/test.sh succeeds.
- **Interfaces:** .gitignore; DECISIONS.md; Sources/i2MessageCore/Permissions/MessagesDataAccessPermissionManager.swift; Sources/i2MessageCore/DataAccess/MessagesDataAccessStack.swift; docs/data-access.md
- **By:** n1 · 2026-07-04T02:12:47.604Z

## n5: Wired end-to-end live app composition with fixture fallback and performance smoke
- **Did:** Integrated the n1 read-only Messages/Contacts stack, n2 `LocalSearchService`, n3 safe Messages parity actions, and n4 SwiftUI shell through `AppDependencies.live()`. The app now launches from fixture seed data, hydrates real bounded pages when permissions allow, starts exact/semantic indexing in the background, observes repository changes to invalidate/rebuild search, routes search results into transcript anchor pages, uses safe Messages.app send/handoff, persists settings locally, and logs diagnostics without message contents. Added app integration/performance tests and docs/performance.md with measured synthetic results.
- **Interfaces:** `AppDependencies.live(configuration:fileManager:)`; `AppDependencies.fixture(...)`; `AppDependencies.indexedFixture(...)`; `CompositeAppPermissionManager`; `RepositorySearchIndexCorpusProvider`; `UserDefaultsSettingsStore`; `AppDiagnostics`; `AppViewModel.actionAvailabilitySnapshot`; `AppViewModel.openSelectedConversationInMessages()`; `Tests/i2MessageAppTests/Integration/AppIntegrationPerformanceTests.swift`; `docs/performance.md`.
- **Measured:** 120-conversation/12,000-message synthetic fixture: launch 1 ms, transcript older-page load 0.2 ms, exact search first page 2.6 ms, semantic first results 354 ms, transcript route 0.1 ms.
- **Follow-ups:**
  - Run real-account Messages send/Automation/Full Disk Access QA [out of lane] — TCC prompts and Messages account state cannot be fully automated in CI.
  - Tune semantic indexing for very large histories [out of lane] — Current bounded vector scan meets the 12,000-message target; ANN indexing may be needed for much larger accounts.
- **By:** n5 · 2026-07-04T12:14:00-07:00

## n5: Resolved all n5 jj merge conflicts by keeping the
- **Did:** Resolved all n5 jj merge conflicts by keeping the live AppViewModel/AppDependencies integration, preserving combined ignore rules and the clean n5 decision log, deleting obsolete MockInboxViewModel, and retaining the polished SwiftUI conversation/sidebar/content views with live search, permissions, parity, and handoff UI. Verified with ./scripts/verify.sh: project generation, Debug macOS build, and full tests passed; jj resolve --list reports no conflicts.
- **Interfaces:** .gitignore; DECISIONS.md; Sources/i2MessageApp/Views/ContentView.swift; Sources/i2MessageApp/Views/ConversationDetailView.swift; Sources/i2MessageApp/Views/SidebarView.swift; removed Sources/i2MessageApp/Mock/MockInboxViewModel.swift; AppViewModel/AppDependencies live integration remains the app boundary.
- **Follow-ups:**
  - Real-account macOS QA [out of lane] — Full Disk Access, Contacts, Apple Events prompts, Messages account state, and real send/handoff flows still require a signed local app on a user account with Messages history.
- **By:** n5 · 2026-07-04T19:22:50.727Z

## n6: Added a repeatable macOS release pipeline: resolved inherited AppViewModel
- **Did:** Added a repeatable macOS release pipeline: resolved inherited AppViewModel merge conflicts, added tag-triggered GitHub Actions release workflow, Developer ID signing/keychain import scripts, app and DMG notarization/stapling/Gatekeeper validation, checksum generation, unsigned local dry-run packaging, and release docs. Verified script syntax, workflow YAML parsing, dry-run env validation, fail-fast missing-secret validation, unsigned Release DMG creation/mount validation/checksum, and ./scripts/test.sh.
- **Interfaces:** .github/workflows/release.yml; scripts/release/common.sh; validate-env.sh; import-developer-id-certificate.sh; build-archive.sh; local-dry-run.sh; ci-release.sh; package-dmg.sh; validate-app.sh; validate-dmg.sh; notarize.sh; staple-and-assess.sh; checksums.sh; zip-app.sh; docs/release.md; docs/release-signing.md; README release references; secrets APPLE_TEAM_ID, DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64, DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD, KEYCHAIN_PASSWORD, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8, APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD
- **Follow-ups:**
  - Configure real Apple Developer and notarization secrets [out of lane] — Production signing/notarization cannot run until the repository has real Developer ID and App Store Connect or Apple ID fallback credentials.
  - Cut a v* release tag and review the first signed release artifact [out of lane] — The implemented workflow is ready, but the first signed/notarized GitHub Release needs real secret-backed CI execution and manual artifact sanity review.
- **By:** n6 · 2026-07-04T19:37:22.884Z

## n7: Completed final QA polish and release readiness pass
- **Did:** Resolved inherited n7 conflicts while preserving the n5 live AppViewModel/AppDependencies integration and n6 release pipeline, fixed the sidebar permission footer request action, updated deprecated SwiftUI `onChange` handlers, added a shared `I2VerticalDivider`, made the Contacts detail layout responsive for small windows, verified script/plist syntax, `./scripts/verify.sh`, synthetic performance, unsigned release DMG dry-run, credential validation behavior, and privacy scans, and added `docs/ship-checklist.md`.
- **Interfaces:** `.gitignore`; `DECISIONS.md`; `docs/ship-checklist.md`; `Sources/i2MessageApp/DesignSystem/I2DesignSystem.swift` `I2VerticalDivider`; `Sources/i2MessageApp/Features/Contacts/ContactsWorkspaceView.swift`; `Sources/i2MessageApp/Views/SidebarView.swift`; `Sources/i2MessageApp/Views/ContentView.swift`; `Sources/i2MessageApp/Views/ConversationDetailView.swift`; removed obsolete `Sources/i2MessageApp/Mock/MockInboxViewModel.swift`.
- **Measured:** 120-conversation/12,000-message synthetic fixture: launch 0.1463s, transcript older-page load 0.0002s, exact search first page 0.0035s, semantic first results 0.3525s, transcript route 0.0001s. Unsigned DMG: `build/Release/i2Message-0.1.0-unsigned.dmg`, SHA-256 `c513ac83aeabd6d325799695a30104fa4736dbb8878898821b0e9b2f0d1adf8e`.
- **Follow-ups:**
  - Run real-account macOS TCC and Messages send QA [out of lane] — Full Disk Access, Contacts, Automation, Notifications, and real Messages account behavior require the signed app on the user's account.
  - Configure Apple Developer signing/notarization secrets [out of lane] — Developer ID signing, notarization, stapling, Gatekeeper assessment of signed artifacts, and GitHub Release publication require real repository secrets.
- **By:** n7 · 2026-07-04T20:00:00Z
## n7: Resolved all n7 jj merge conflicts by preserving the
- **Did:** Resolved all n7 jj merge conflicts by preserving the final-QA/live AppViewModel side, keeping the n6 release pipeline, deleting obsolete MockInboxViewModel, updating docs/ship-checklist.md with fresh verification metrics, and rerunning readiness checks. Verification passed: script syntax, plist lint, workflow YAML parse, privacy/secret scans, ./scripts/verify.sh, isolated synthetic performance benchmark, unsigned release dry run, checksum validation. Credentialed release validation fails only for missing Apple Developer/notarization secrets as expected.
- **Interfaces:** .gitignore; DECISIONS.md; docs/ship-checklist.md; Sources/i2MessageApp/Views/ContentView.swift; Sources/i2MessageApp/Views/ConversationDetailView.swift; Sources/i2MessageApp/Views/SidebarView.swift; removed Sources/i2MessageApp/Mock/MockInboxViewModel.swift; unsigned artifact build/Release/i2Message-0.1.0-unsigned.dmg SHA-256 1ccc474b645e0e8cc76ad5c2bb1d085800c63d10a79822c91654fcb9f3e50d11
- **Follow-ups:**
  - Run real-account macOS QA [out of lane] — Full Disk Access, Contacts, Automation, Notifications, and real Messages send/handoff behavior require the signed app on the user account with real local history.
  - Configure Apple release secrets [out of lane] — Developer ID signing, notarization, stapling, Gatekeeper assessment of signed artifacts, and GitHub Release publication require real repository secrets.
  - Update local Xcode/CoreSimulator install [out of lane] — Xcode reports CoreSimulator 1051.54.0 older than build version 1051.55.0; it did not block macOS build/test/release dry-run paths but should be cleaned up on the machine.
- **By:** n7 · 2026-07-04T20:04:58.287Z

## n8: n8 terminal push/privacy gate ran from main checkout /Users/viraat/code/i2messa…
- **Did:** n8 terminal push/privacy gate ran from main checkout /Users/viraat/code/i2message after RUDDER showed n1-n7 merged and only coordinator+self active. Inspected required docs/scripts/workflows/remotes/tags. ./scripts/verify.sh passed. ./scripts/release/local-dry-run.sh passed and produced build/Release/i2Message-0.1.0-unsigned.dmg SHA-256 28207263f8c398f064cffaabdca58f47367aa243d625b16ea51174b036450ebf. Signed archive path was skipped precisely because ./scripts/release/validate-env.sh --release returned 64 for missing APPLE_TEAM_ID, Developer ID cert/password/keychain password, and notarization credentials. Privacy audit passed for tracked paths, tracked binary/media, secret/token patterns, JJ diff content, tags (none), and DMG contents; only reviewed generic chat.db docs/diagnostic references and synthetic example.com/555 fixtures. No push performed because status/push gate failed: git status --short --branch reports detached HEAD with unmerged index entries including .jj-do-not-resolve-this-conflict plus UU/UD app files; jj has final n7 merge content in @ with diff, main bookmark still points at initial commit 04d6cfd, git HEAD is n6 e8a25eb, and no local tags exist. Remote origin is https://github.com/viraatdas/i2message.git; remote main is still 04d6cfd. GitHub release workflow could not start because no branch/tag was pushed.
- **Interfaces:** No code interfaces created or changed by n8. Assumed final app/release interfaces from merged n1-n7; generated ignored build artifacts under build/Release only.
- **Follow-ups:**
  - Export/repair jj-to-git main checkout state before pushing [out of lane] — The gate cannot safely push while Git is detached with unmerged index entries and the main bookmark still targets the initial commit instead of the final n7 merge.
  - Cut and push release tag after branch state is clean [out of lane] — No local tags exist; v0.1.0 is only inferred from MARKETING_VERSION, and the GitHub Releases workflow starts on pushed v* tags.
  - Configure Apple Developer signing and notarization secrets [out of lane] — Production signed archive/notarization is blocked solely by missing Apple Developer certificate/keychain and notarization credentials.
- **By:** n8 · 2026-07-04T20:10:48.764Z

## worker: Repaired the main checkout/ref state to the final verified
- **Did:** Repaired the main checkout/ref state to the final verified Rudder merge commit 43c330ed741d2d606935af13722ef3833ddbde6c, attached the checkout to main, pushed origin/main, created and pushed v0.1.0, and checked the GitHub Release workflow. Verification passed locally: ./scripts/verify.sh passed; ./scripts/release/local-dry-run.sh passed and produced build/Release/i2Message-0.1.0-unsigned.dmg with SHA-256 55877d3dd970996cf45c9aa0b4667544cfaa040186d64bc939f662c6fa1500a9. Privacy audit passed for tracked files, origin/main..HEAD diff, planned/pushed tag, and the mounted DMG. ./scripts/release/validate-env.sh --release is still blocked by missing Apple Developer/notarization environment variables. GitHub Actions Release run 28764151051 started for v0.1.0 but failed in the Test step on LocalSearchServiceTests.testSemanticIndexCanResumeAfterCancellation(), so release artifact/signing/upload steps were skipped.
- **Interfaces:** origin https://github.com/viraatdas/i2message.git; branch main; commit 43c330ed741d2d606935af13722ef3833ddbde6c; tag v0.1.0; workflow .github/workflows/release.yml; local unsigned artifact build/Release/i2Message-0.1.0-unsigned.dmg and build/Release/SHA256SUMS.txt
- **Follow-ups:**
  - Fix CI-only semantic cancellation test failure [out of lane] — The tag-triggered Release workflow failed before artifact/signing steps because LocalSearchServiceTests.testSemanticIndexCanResumeAfterCancellation() failed on GitHub Actions, even though local ./scripts/verify.sh passed before pushing.
  - Configure Apple Developer and notarization secrets [out of lane] — Production signed/notarized release remains blocked by missing APPLE_TEAM_ID, Developer ID certificate/password/keychain password, and App Store Connect or Apple ID notarization credentials.
- **By:** worker · 2026-07-06T02:39:13.451Z

## Plan approved
- **What:** Approved a 6-task plan for: - there should be no reply in the thing - have a way to put any emoji or like emoji picker - improve the the swipe into the thread panel animation it's buggy - scorlling down and whanto tther eis a lot of bugs - check for memory leaks make sure it's not getting fucked up. Tasks: Remove inline reply affordance; Add arbitrary emoji picker; Stabilize swipe and thread animation; Fix long transcript scrolling; Audit lifecycle and memory leaks; Final integration QA.
- **Why:** user-approved plan; workers implement these nodes in isolated workspaces, honoring the dependency edges
- **By:** conductor · 1783469440645

## worker: Verified main checkout after prior repair: origin/main is 63e09ac967cde896bf009…
- **Did:** Verified main checkout after prior repair: origin/main is 63e09ac967cde896bf00932ce365c7e7d4331b09, v0.1.0 exists remotely at 43c330ed741d2d606935af13722ef3833ddbde6c, ./scripts/verify.sh passed, ./scripts/release/local-dry-run.sh passed with unsigned DMG SHA-256 f326752c762a7e2a94eda4c9d28e48b6dec1e24c716457d46cdc72987ff235b9, release env validation is blocked only by missing Apple signing/notarization variables, tracked/tag/diff/artifact privacy audits passed, and idempotent pushes for origin main and refs/tags/v0.1.0 returned Everything up-to-date. GitHub Release workflow run 28764151051 for v0.1.0 is completed failure in the Test step; no GitHub Release exists.
- **Interfaces:** origin https://github.com/viraatdas/i2message.git; branch main -> 63e09ac967cde896bf00932ce365c7e7d4331b09; tag v0.1.0 -> 43c330ed741d2d606935af13722ef3833ddbde6c; workflow .github/workflows/release.yml; artifact build/Release/i2Message-0.1.0-unsigned.dmg; checksum build/Release/SHA256SUMS.txt
- **Follow-ups:**
  - Decide how to release current main after v0.1.0 [out of lane] — The remote v0.1.0 tag already exists on 43c330ed while origin/main has advanced to 63e09ac, so I did not move the published tag without explicit instruction.
  - Fix or rerun tag Release workflow [out of lane] — GitHub Actions run 28764151051 for v0.1.0 failed in the Test step before artifact build/upload/release creation.
  - Configure Apple release secrets [out of lane] — Signed Developer ID archive, notarization, stapling, Gatekeeper assessment, and signed GitHub Release publication require the missing Apple Developer/notarization secrets.
- **By:** worker · 2026-07-08T00:12:36.830Z

## n9: Removed the main transcript inline reply flow: no Reply
- **Did:** Removed the main transcript inline reply flow: no Reply context-menu command, no composer reply banner, and normal composer sends always carry nil replyToMessageID. Preserved thread-panel replies through sendThreadReply/openThread, updated AppViewModel tests for normal send vs panel reply, updated docs/ui.md, and verified generate-xcodeproj, test, and build all pass. xcodebuild still reports the existing non-blocking CoreSimulator version warning.
- **Interfaces:** Sources/i2MessageApp/Views/ConversationDetailView.swift ComposerView/MessageBubble context menu; Sources/i2MessageApp/Features/App/AppViewModel.swift sendCurrentDraft/sendThreadReply/openThread; Tests/i2MessageAppTests/UIModel/AppViewModelTests.swift; docs/ui.md
- **Follow-ups:**
  - Update local CoreSimulator install [out of lane] — xcodebuild reports CoreSimulator 1051.54.0 older than build 1051.55.0, though macOS generation, tests, and build still pass.
- **By:** n9 · 2026-07-08T00:14:54.009Z

## n10: Added arbitrary emoji insertion and safe custom reactions
- **Did:** Added a reusable native SwiftUI emoji popover with common emoji, arbitrary emoji text entry, and macOS Character Viewer handoff; wired explicit emoji insertion into the main composer and thread composer; added fixture-only custom emoji reactions through `MessageReactionKind.custom/displayText`; updated UI-model coverage and docs.
- **Interfaces:** `Sources/i2MessageApp/Views/EmojiPickerControl.swift` with `EmojiCatalog.normalizedEmoji(from:)`, `EmojiPickerControl`, and `EmojiPickerPopover`; `AppViewModel.insertEmojiInCurrentDraft(_:)`; `AppViewModel.insertEmojiInThreadDraft(_:)`; `AppViewModel.toggleCustomReaction(_:on:)`; composer wiring in `ConversationDetailView` and `ThreadPanelView`; tests in `AppViewModelTests`; docs in `docs/ui.md`.
- **Safety:** Custom reactions mutate only fixture/fixture-backed transcript state. Real live transcripts show an info banner and leave reactions unchanged, preserving the no-direct-Messages-database-write rule.
- **Verified:** `./scripts/generate-xcodeproj.sh`, `./scripts/test.sh`, and `./scripts/build.sh` passed. Xcode still reports the existing non-blocking CoreSimulator 1051.54.0 vs 1051.55.0 warning.
- **Follow-ups:**
  - Update local CoreSimulator install [out of lane] — The warning is unchanged from n9 and did not block macOS generation, tests, or build.
- **By:** n10 · 2026-07-08T00:22:00Z
## n10: Resolved the DECISIONS.md jj merge conflict for n10 by
- **Did:** Resolved the DECISIONS.md jj merge conflict for n10 by keeping one consolidated arbitrary-emoji/custom-reaction decision entry, preserving the safety note and verification record. Verified jj reports no conflicts, ./scripts/generate-xcodeproj.sh passed, ./scripts/test.sh passed, and ./scripts/build.sh passed with the known CoreSimulator warning.
- **Interfaces:** DECISIONS.md n10 decision log entry only; no code interfaces changed by this conflict resolution.
- **Follow-ups:**
  - Update local CoreSimulator install [out of lane] — Xcode still reports CoreSimulator 1051.54.0 older than build 1051.55.0 during macOS build/test, though verification passed.
- **By:** n10 · 2026-07-08T00:23:26.945Z

## n11: Stabilized swipe-to-thread by extracting ThreadSwipeGestureState, passing verti…
- **Did:** Stabilized swipe-to-thread by extracting ThreadSwipeGestureState, passing vertical and momentum scroll through, enforcing one thread open per gesture, clearing partial swipe state on hover/message/conversation/disappear/end changes, replacing the thread panel move transition with a fixed-width opacity dock, and honoring reduced motion for bubble, panel, and thread auto-scroll movement. Verified generate-xcodeproj, test, build, and mock launch.
- **Interfaces:** Sources/i2MessageApp/Views/ThreadSwipeGestureState.swift; ThreadPanelDock in ContentView; I2Motion.threadPanel(reduceMotion:); I2Motion.swipeReset(reduceMotion:); I2Layout.hairlineWidth/threadPanelDockWidth; AppViewModel conversation/contact thread reset behavior; ThreadSwipeGestureStateTests; AppViewModelTests.testChangingConversationClosesThreadPanel; docs/ui.md swipe/panel contract; DECISIONS.md n11 entry
- **Follow-ups:**
  - Update local CoreSimulator install [out of lane] — Xcode still warns CoreSimulator 1051.54.0 is older than build 1051.55.0; macOS generation, tests, build, and mock launch all passed despite it.
- **By:** n11 · 2026-07-08T02:57:15.197Z


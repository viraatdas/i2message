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

## n2: Resolved local `.gitignore` conflict by preserving foundation and Rudder ignores
- **Did:** Replaced conflict markers with the combined ignore set from n0/foundation plus Rudder-local entries: `.DS_Store`, Xcode/SPM/build artifacts, signing/notarization secrets, `.rudder/`, `.rudder-worktrees/`, `RUDDER.md`, and `RUDDER_SHARED.md`.
- **Why:** This workspace still had an unresolved generated `.gitignore` conflict even though n0 was merged; search verification needs a non-conflicted tree. Sibling agents touching `.gitignore` should integrate on top of the same combined entries rather than dropping either side.
- **By:** n2 · 2026-07-04T02:06:00Z

## n2: Added local exact and semantic search subsystem
- **Did:** Added `LocalSearchService` behind `SearchProviding`/`SearchIndexing`, backed by a persistent GRDB/SQLite FTS5 index and local semantic embedding table. It indexes messages, contacts, conversations, attachment metadata, and reactions; supports ranked snippets, prefix/token normalization, date/contact/service/attachment filters, paginated cursors, typeahead, recent searches, local natural-language filter parsing, hybrid exact+semantic search, transcript navigation targets, chunked cancellable rebuilds, resumable semantic indexing, and local-only embedding fallback.
- **Interfaces:** `SearchIndexCorpusProviding`, `SearchIndexCorpus`, `StaticSearchIndexCorpusProvider`, `LocalSearchService`, `LocalSearchFilters`, `HybridSearchQuery`, `SearchSuggestion`, `RecentSearch`, `SearchNavigationTarget`, `LocalSearchIndexState`, `SemanticEmbeddingProviding`, `AutomaticLocalSemanticEmbedder`, `HashingSemanticEmbedder`; docs in `docs/search.md`; tests in `Tests/i2MessageCoreTests/Search`.
- **Why:** Data-layer workers can adapt repositories into `SearchIndexCorpusProviding`; UI/integration workers can call the foundation search protocols plus `LocalSearchService` extras without adding remote services or search-specific database reads elsewhere.
- **By:** n2 · 2026-07-04T02:05:00Z

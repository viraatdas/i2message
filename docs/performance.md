# Performance

i2Message should show useful UI immediately, then hydrate real Messages data and local indexes without blocking the first window.

## Targets

| Workflow | Target | Measured synthetic result |
| --- | ---: | ---: |
| App launch to loaded fixture shell | < 750 ms | 316 ms |
| Conversation transcript older-page load | < 150 ms | 1.8 ms |
| Exact search first page after local index is warm | < 250 ms | 2.9 ms |
| Semantic search first usable local results after embeddings are warm | < 1,000 ms | 356 ms |
| Search-result transcript route and anchor-page load | < 250 ms | 0.6 ms |

Measurements were taken on July 8, 2026 with:

```sh
xcodebuild -project i2Message.xcodeproj \
  -scheme i2Message \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -destination platform=macOS \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:i2MessageAppTests/AppIntegrationPerformanceTests/testSyntheticPerformanceBudgets
```

The benchmark writes a generated report to `build/performance/app-synthetic-results.json`. The fixture contains 120 synthetic conversations and 12,000 synthetic messages; it does not read real Messages data.

## Launch Shape

- `i2MessageApp` constructs `AppDependencies.live()` for production.
- `AppViewModel` starts from an in-memory fixture seed so the split view can render immediately.
- Real read-only Messages/Contacts repositories hydrate bounded conversation/contact pages after launch.
- Exact and semantic indexing starts in a background task after the first load path; the app does not wait for full indexing before showing conversations.
- Search uses the persistent local SQLite/FTS/embedding index once warm. Before embeddings exist, semantic search returns quickly with the locally indexed subset available.

## Current Bottlenecks

- Full semantic rebuild still scans locally stored vectors instead of using an ANN index. First usable search is within target on the 12,000-message fixture, but very large histories may need an ANN-backed semantic index if scans exceed the 1 second target.
- The repository-backed search corpus currently materializes messages per conversation during background indexing. This keeps launch fast, but very large accounts should tune `RepositorySearchIndexCorpusProvider` chunking before raising fixture sizes by orders of magnitude.
- Real Messages permissions cannot be fully automated in CI; Full Disk Access and Automation prompts require manual local QA.

## Manual Smoke Checklist

Run automated verification first:

```sh
./scripts/generate-xcodeproj.sh
./scripts/build.sh
./scripts/test.sh
```

Then on a macOS account with Messages history:

1. Launch `i2Message` and confirm the window appears immediately with fixture or real conversations.
2. Open Settings and request Full Disk Access, Contacts, Messages Automation, and Notifications as needed. Confirm each route opens the relevant macOS settings or prompt.
3. After granting Full Disk Access, relaunch and confirm real conversations replace the fixture seed without a blocking full-index wait.
4. Select a long thread, load earlier pages, and confirm the transcript remains responsive and keeps the previous top visible message anchored instead of jumping to the bottom.
5. Rebuild local indexes from Diagnostics or Settings, then run exact search for a known phrase and open a result. Confirm the transcript routes to the highlighted message.
6. Run semantic search for an idea rather than exact wording. Confirm local snippets appear and route back into transcripts.
7. Send a short test iMessage to a safe recipient. Confirm Messages.app handles the send, i2Message updates local UI, scrolls to the local send, and the read-only transcript refresh catches up without snapping older-history readers to the bottom for unrelated arrivals.
8. Try an unsupported action path such as group/SMS direct send or mark-read. Confirm i2Message uses handoff/unavailable messaging rather than mutating private Messages storage.
9. Inspect logs with Console. Confirm diagnostics include event names, durations, counts, and states only, not message bodies, handles, contact names, attachment paths, or phone/email values.

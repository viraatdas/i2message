# Search

i2Message search is local-only. Message bodies, contacts, attachment metadata, reactions, exact-search indexes, and semantic embeddings stay on disk in the app's local SQLite index. The search subsystem does not call a remote embedding service.

## Components

- `LocalSearchService` conforms to the foundation `SearchProviding` and `SearchIndexing` protocols.
- `SearchIndexCorpusProviding` is the integration boundary for real Messages/Contacts data. Data-layer workers can feed conversations, contacts, and messages into this provider without search reading `chat.db` directly.
- `LocalSearchIndex` owns the persistent SQLite schema, FTS5 exact index, semantic embedding table, recent-search table, resumable indexing checkpoints, and paginated cursor reads.
- `AutomaticLocalSemanticEmbedder` uses Apple NaturalLanguage sentence embeddings when available and falls back to `HashingSemanticEmbedder`, a deterministic offline embedding model with a small local synonym table.

## Exact Search

Exact search uses SQLite FTS5 with the `unicode61` tokenizer, diacritic-insensitive normalization, prefix indexes, BM25 ranking, and stable offset cursors. It indexes:

- message text and reactions
- conversation titles, participants, and latest previews
- contacts and handles
- attachment filenames, UTIs, kind, byte count, and associated message text

`ExactSearchQuery` supports conversation, sender/contact, date, and attachment filters. `LocalSearchFilters` adds a service filter for local hybrid APIs.

### Full-history, streaming ingestion

The exact index covers the ENTIRE Messages history — every conversation and every message — with no caps. To keep memory bounded on large libraries (~700k messages), `rebuildExactIndex` never materializes the full corpus: it loads a small skeleton (all conversations + contacts) via `SearchIndexCorpusProviding.corpusSkeleton()` and streams each conversation's messages in paged batches via `messageBatches(in:batchSize:)`.

Rebuilds are incremental and resumable at conversation granularity. Each completed conversation records a content signature (`indexed_conversations` table); a later pass skips streaming any conversation whose signature is unchanged, so a background reindex after one new message re-reads only the affected conversation. Within a changed conversation, per-document hash comparison ensures unchanged rows are never rewritten (a rewrite would cascade-delete the row's semantic embedding).

`scripts/real-db-index-check.sh` runs an env-gated harness (`I2MESSAGE_REAL_DB_CHECK=1`) that builds the index from a temporary copy of the real `chat.db` and asserts full coverage plus old-message findability. It requires Full Disk Access and leaves no artifacts.

## Semantic Search

Semantic indexing stores normalized vectors in SQLite as local BLOBs. `rebuildSemanticIndex` only embeds documents whose hash/model pair is missing or stale, so interrupted runs can resume without recomputing completed chunks.

Search computes the query embedding locally and scores stored vectors with cosine similarity. For large histories, the implementation uses a pragmatic bounded scan (`semanticCandidateLimit`, default 20,000) rather than adding an undeclared ANN dependency. This is fast enough for current fixture sizes and keeps the dependency surface aligned with the foundation manifest.

Unlike the exact index, the semantic index is deliberately bounded: only the most recent `semanticCandidateLimit` documents are eligible for embedding (production passes `AppDependencies.semanticEmbeddingBudget` = 50,000), embedded newest-first. Embedding all ~700k documents of a large library locally is prohibitive; exact search still covers everything.

While embeddings are still building, semantic search returns ranked results from the documents already embedded. If no embeddings exist yet, it returns an empty result quickly instead of blocking UI queries.

## Indexing

`rebuildExactIndex` and `rebuildSemanticIndex`:

- prepare the SQLite schema lazily
- process documents in chunks
- call `Task.checkCancellation()` between chunks and expensive work
- persist checkpoint metadata after each successful chunk
- yield between chunks so UI queries can run
- report progress as `0...1`

App launch should call `prepare()` or start indexing in a background task; it should not wait for full indexing before showing conversations.

## Additional APIs

`LocalSearchService` also exposes:

- `hybridSearch(_:page:)` for ranked exact + semantic results
- `typeaheadSuggestions(for:limit:)`
- `recentSearches(limit:)`
- `interpretNaturalLanguageQuery(_:)` for local-only parsing of simple `service:`, `after:`, `before:`, `from:`, and `in:` filters
- `navigationTarget(for:)` to jump from a result into a transcript
- `localIndexState()` for diagnostics and progress UI

## Benchmarks

The unit test `testExactSearchFirstPageIsFastOnSyntheticLargeFixture` builds an 8,000-message synthetic corpus with 200 matching messages and asserts the first exact-search page returns in under one second after indexing.

Run:

```sh
./scripts/generate-xcodeproj.sh
./scripts/test.sh
```

Expected behavior on a local macOS development machine:

- first exact page over the synthetic fixture is comfortably sub-second
- exact pagination returns stable cursors and total counts
- semantic indexing can be cancelled and resumed
- semantic fallback returns offline ranked results without a remote provider

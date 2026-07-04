# Messages and Contacts Data Access

The production data layer lives under `Sources/i2MessageCore/DataAccess`, `Sources/i2MessageCore/Contacts`, and `Sources/i2MessageCore/Permissions`.

## Safety Guarantees

- `ReadOnlyMessagesStore` opens `chat.db` with `SQLITE_OPEN_READONLY`.
- The connection immediately enables `PRAGMA query_only = ON`.
- The store rejects any connection that does not report `sqlite3_db_readonly(..., "main") == 1`.
- Tests generate temporary synthetic SQLite databases and never read `~/Library/Messages/chat.db`.
- Attachment records are read lazily through `AttachmentRepository`; thumbnails are not generated or persisted by this layer.
- Contacts photo thumbnails are kept in memory by `SystemContactsProvider` and are not written to disk.

## Default Locations

`MessagesStoreConfiguration()` points at:

- Database: `~/Library/Messages/chat.db`
- Attachments: `~/Library/Messages/Attachments`

Apps can pass a user-selected `chat.db` URL into `MessagesStoreConfiguration(databaseURL:attachmentsDirectoryURL:)`.

## Permissions and Diagnostics

`MessagesStoreDiagnosticService` reports:

- missing database
- likely missing Full Disk Access
- corrupt or non-SQLite database
- unsupported Messages schema
- read-only open failures

`MacOSPermissionManager` reports Full Disk Access by attempting a safe read-only open. macOS does not provide a programmatic Full Disk Access prompt, so `request(.fullDiskAccess)` opens System Settings and returns the current status.

Contacts access uses `CNContactStore.authorizationStatus` and `requestAccess(for: .contacts)`.

## Schema Tolerance

`MessagesDatabaseSchema` introspects available tables and columns with `sqlite_master` and `PRAGMA table_info`. Repositories require only the core Messages tables:

- `chat`
- `message`
- `handle`
- `chat_message_join`

Optional columns such as `message_date`, `is_muted`, `is_pinned`, `cache_has_attachments`, `thread_originator_guid`, and attachment metadata are used when present and fall back to `NULL` or conservative defaults when absent.

## Pagination and Loading

Conversation pages are bounded by `PageRequest.limit` and `MessagesStoreConfiguration.maximumPageSize`. They read chat rows plus a latest-message subquery and do not scan or materialize all messages at startup.

Transcript pages are fetched newest-first. Stable cursors encode the raw Messages sort timestamp and row id:

```text
message:v1:<sort-value>:<rowid>
conversation:v1:<sort-value>:<rowid>
```

Older and newer paging use those cursor fields instead of offset paging, so inserts do not shift existing pages.

`observeConversations` and `observeMessages` use `PollingMessagesChangeMonitor`, which watches `chat.db`, `chat.db-wal`, and `chat.db-shm` metadata and reloads only bounded pages when the token changes.

## Benchmarks

`MessagesDataAccessPerformanceTests` builds synthetic databases in temporary directories:

- 160 conversations x 50 messages for conversation paging
- 20 conversations x 300 messages for transcript paging

The tests assert bounded page sizes and a local smoke threshold under 2 seconds for each first-page fetch. They are intended as regression smoke tests, not full hardware-normalized benchmarks.

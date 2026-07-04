# i2Message Native UI

The SwiftUI shell is built around `AppViewModel` in `Sources/i2MessageApp/Features/App`. It consumes the foundation protocols from `i2MessageCore` through `AppDependencies`, with mock providers in this UI lane for local development.

## Implemented Workflows

- Conversations sidebar with all/unread/pinned/muted filters, unread badges, pinned/muted indicators, attachment hints, stable row sizing, and keyboard next/previous selection.
- Contacts workspace with handle details, shared thread navigation, contact search, and mock message actions.
- Transcript detail with lazy `ScrollView`/`LazyVStack` rows, older-page loading, highlighted search result scrolling, tapbacks, edited/failed states, and attachment transfer states.
- Composer with draft text, mock attachments, drag/drop attachment intake, Command-Return send, validation errors, and mock sent-message insertion through `MessageSending`.
- Exact search workspace with scoped conversation search, paged result loading, result previews, attachment/contact/conversation hits, and highlighted snippets.
- Semantic search workspace with local mock snippets, similarity labels, source message counts, hybrid mode, and transcript jump targets.
- Settings window/sheet for theme, transcript density, page size, permissions, exact/semantic index toggles, privacy defaults, indexing progress, and mock offline/error states.
- Command palette for new message, search, sidebar filter focus, conversation navigation, semantic toggle, settings, local index rebuild, offline mode, and error preview.
- Loading skeletons, empty states, error banners, permission states, offline cache banner, and indexing progress states.

## Protocol Boundary

The UI currently uses:

- `ConversationRepository`
- `MessageRepository`
- `ContactProviding`
- `SearchProviding`
- `SearchIndexing`
- `PermissionManaging`
- `SettingsStoring`
- `MessageSending`

Real data/search/action workers should replace the mock providers by constructing an `AppDependencies` value with production implementations. The UI does not mutate Messages storage directly.

## Performance Shape

- Transcript rows are lazy and load only the visible page plus explicitly requested older pages.
- Search results are paged with `PageCursor`; semantic snippets are limited by query.
- Attachments render as lightweight chips in the transcript and inspector. Future image thumbnail loading should stay lazy at the attachment component boundary.
- UI state is keyed by `ConversationID`, so loading older messages or sending in one thread does not replace every transcript.

## Visual QA Notes

The interface follows the product design direction in `DESIGN.md`: native macOS split view, restrained system surfaces, amber accent only for selection/search/primary actions, compact typography, no marketing hero screens, no nested card layouts, and no decorative glass/gradient effects.

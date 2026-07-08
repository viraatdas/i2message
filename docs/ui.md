# i2Message Native UI

The SwiftUI shell is built around `AppViewModel` in `Sources/i2MessageApp/Features/App`. It consumes the foundation protocols from `i2MessageCore` through `AppDependencies`, with live providers for the app target and fixture providers for previews/tests.

## Implemented Workflows

- Conversations sidebar with all/unread/pinned/muted filters, unread badges, pinned/muted indicators, attachment hints, stable row sizing, and keyboard next/previous selection.
- Contacts workspace with handle details, shared thread navigation, contact search, and mock message actions.
- Transcript detail with lazy `ScrollView`/`LazyVStack` rows, older-page loading that preserves the previous top visible message, explicit highlighted search result scrolling, local-send bottom scrolling, emoji tapback badges on bubble corners, a per-bubble context menu (standard tapbacks, fixture-only custom emoji reactions, open thread for threaded messages, copy), quoted reply context with jump-to-original, edited/failed states, and attachment transfer states.
- Swipe-to-thread uses a local trackpad scroll monitor only while the transcript is visible, separates horizontal intent from vertical scrolling, passes momentum and vertical deltas through to the transcript, opens at most one thread per gesture, and clears partial swipe state on hover, conversation, message-list, disappear, or gesture-end changes. Reduced Motion removes bubble movement and animated scroll/panel movement.
- Composer with draft text, attachment/drop intake, auto-growing text field, an emoji control with common emoji, arbitrary emoji entry, and macOS Character Viewer handoff, Return-to-send (Shift-Return inserts a newline, Command-Return also sends), validation errors, safe Messages.app send/handoff in live mode, and fixture sent-message insertion in tests/previews through `MessageSending`. The main transcript composer always sends normal conversation messages; anchored replies are panel-only.
- Docked thread panel with root-plus-replies transcript, its own `Reply in thread` composer with the same explicit emoji insertion control, Return-to-send, unread-thread activity state, focused close behavior, and a fixed-width opacity dock that avoids a competing slide transition.
- Exact search workspace with scoped conversation search, paged result loading, result previews, attachment/contact/conversation hits, and highlighted snippets.
- Semantic search workspace with local mock snippets, similarity labels, source message counts, hybrid mode, and transcript jump targets.
- Settings window/sheet for theme, transcript density, page size, permissions, exact/semantic index toggles, privacy defaults, indexing progress, and diagnostics/offline/error states.
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

`AppDependencies.live()` constructs production read-only data, local search, permission, settings, and safe action implementations. `AppDependencies.fixture(...)` and `.indexedFixture(...)` preserve deterministic preview/test providers. The UI does not mutate Messages storage directly.

Custom emoji reactions use `MessageReactionKind.custom` with `displayText` only for fixture/test transcripts or fixture-backed live seed content. Real live transcripts show an info banner and route users to Messages.app for tapbacks/reactions; i2Message does not write reactions into Messages private storage.

## Performance Shape

- Transcript rows are lazy and load only the visible page plus explicitly requested older pages.
- Transcript scroll movement is driven by explicit intents from `AppViewModel`: initial/reset loads go to the newest visible message, search routes center the highlighted row, older-page prepends keep the previous top visible row anchored, and passive live tail refreshes do not snap readers to the bottom.
- Search results are paged with `PageCursor`; semantic snippets are limited by query.
- Attachments render as lightweight chips in the transcript and inspector. Future image thumbnail loading should stay lazy at the attachment component boundary.
- UI state is keyed by `ConversationID`, so loading older messages or sending in one thread does not replace every transcript.

## Visual QA Notes

The interface follows the product design direction in `DESIGN.md`: native macOS split view, restrained system surfaces, amber accent only for selection/search/primary actions, compact typography, no marketing hero screens, no nested card layouts, and no decorative glass/gradient effects.

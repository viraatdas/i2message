# Design

## Design System Overview

i2Message uses a restrained native macOS product interface. The system should look at home beside Finder, Mail, Messages, Linear, and Raycast: familiar controls, dense but breathable information, fast transitions, and one warm accent used for selection and primary actions.

Physical scene: a focused macOS user triaging conversations on a bright laptop display during the workday, with the app open beside notes, browser, and calendar.

Color strategy: restrained. Neutral surfaces carry the app structure; a single amber accent marks selection, search hits, and primary actions.

## Color Palette

Use system dynamic colors in SwiftUI where possible so the app respects Light, Dark, Increase Contrast, and accessibility appearances. Custom brand colors are OKLCH-authored and should be bridged through asset colors or `Color` extensions when needed.

- Background: `oklch(1.000 0.000 0)` in light mode, system window background in dark mode.
- Sidebar surface: `oklch(0.965 0.006 91)` in light mode, system sidebar material in dark mode.
- Content surface: system background.
- Ink: `oklch(0.180 0.012 92)`.
- Muted ink: `oklch(0.470 0.010 92)`.
- Primary accent: `oklch(0.710 0.150 91)`.
- Accent pressed: `oklch(0.630 0.155 91)`.
- Selection fill: primary accent at 12-18% opacity.
- Separator: system separator.
- Success, warning, error, and info: use semantic system colors unless a future design token pass defines app-specific variants.

Accent usage is limited to current selection, primary actions, search highlights, and small state indicators. Do not use decorative gradients or tinted backgrounds to create visual interest.

## Typography

- Font family: SF Pro via SwiftUI system fonts.
- Navigation title: `.title3.weight(.semibold)` or smaller.
- Section headers: `.subheadline.weight(.semibold)`.
- Conversation names: `.body.weight(.medium)`.
- Message body: `.body`.
- Metadata and timestamps: `.caption` or `.caption2`.
- Avoid display fonts, fluid type, negative tracking, and oversized labels inside dense panels.

## Layout

- Main shell: `NavigationSplitView` with a conversation sidebar and transcript detail.
- Minimum useful window size: 920 x 620.
- Sidebar width: 280-360 pt.
- Transcript max line length: keep text bubbles readable, not full-width.
- Use stable row heights for conversation lists and stable message bubble constraints so search/load state changes do not resize the whole layout.
- Cards are reserved for repeated content or tool panes only. Do not nest cards.

## Components

- Sidebar conversation row: avatar, title, timestamp, preview, unread badge, and optional pinned/muted indicators.
- Transcript header: conversation title, participants, search/action buttons.
- Message bubble: direction-aware alignment, readable text, attachment chips, timestamp, delivery state.
- Search field: native searchable placement where possible; exact search and semantic search use the same result vocabulary.
- Skeletons: row-shaped placeholders for loading conversations/messages.
- Empty states: concise native panels that explain the available action without marketing copy.
- Error states: typed error message plus one recovery action where possible.

Every interactive component needs default, hover, focus, active, disabled, loading, and error states before production use.

## Motion

Motion is quick and functional: 150-220 ms for selection, reveal, and loading transitions. Respect Reduce Motion by replacing movement with opacity or immediate state changes. Do not use page-load choreography.

## Accessibility

- VoiceOver labels for message rows, search controls, toolbar actions, permission states, and attachment chips.
- Keyboard navigation for sidebar selection, transcript search, command palette/search entry, and message list focus.
- Visible focus rings should follow macOS conventions.
- Do not rely on color alone for unread, failed, selected, semantic, or permission states.
- Text must remain legible and contained at small window sizes and larger accessibility text sizes.

## Implementation Notes

- Prefer native SwiftUI controls and SF Symbols.
- Use `@Environment(\.accessibilityReduceMotion)` before adding animation.
- Keep real data loading cancellable and paginated.
- Use skeleton rows instead of centered spinners for list and transcript loading.
- Keep privacy-sensitive strings out of logs, analytics, and crash breadcrumbs.

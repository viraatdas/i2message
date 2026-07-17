# Messages.app Parity Matrix

i2Message must never write directly to `~/Library/Messages/chat.db`, WAL files, attachments, or private Messages state. Read access belongs to the read-only data layer; mutations and handoffs in this document use user-approved macOS surfaces only.

## Action Matrix

| Capability | Status | Supported mechanism | Reason / constraint | Fallback UX | Automated tests |
| --- | --- | --- | --- | --- | --- |
| Send single-recipient iMessage text | Implemented with permission | Messages.app Apple Events via `NSAppleScript` | Requires Automation approval for i2Message controlling Messages.app. AppleScript confirms script execution but does not return a stable Messages `messageID`. | If permission is missing or automation fails, copy the draft and open Messages.app for manual send. | `SafeMessagingActionServiceTests.testGrantedSendExecutesAutomationAndReturnsReceiptWithoutPrivateMessageID`, command builder tests |
| Send SMS/MMS/RCS | Handoff only | Open Messages.app and pasteboard handoff | macOS does not expose reliable carrier/SMS send state through public Messages Apple Events. Text Message Forwarding must be verified in Messages.app. | Copy draft and open Messages.app. User sends from Apple's UI. | `MessagesAppleScriptCommandBuilderTests.testSMSDirectSendIsUnavailableByDefault` |
| Start one-recipient iMessage conversation | Implemented with permission | Messages.app Apple Events to an iMessage buddy | Safe only when a concrete handle is available and the requested service is iMessage. | Open Messages.app with recipient/draft copied. | command builder tests |
| Start group conversation | Handoff only | Pasteboard + Messages.app open | AppleScript does not expose a safe public way to create a true group chat from arbitrary handles without risking separate sends. | Copy participants/draft and open Messages.app. | command builder group rejection path covered by service validation behavior |
| Reply to a specific message | Unsupported, graceful | None | Messages AppleScript can send to a buddy/chat, but cannot anchor to a specific bubble or inline reply thread. | Open Messages.app and use the native reply UI. | `MessagesAppleScriptCommandBuilderTests.testReplyCommandIsRejectedBecauseAppleScriptCannotAnchorReplies` |
| Edit sent message text | Guided handoff | In-app replacement editor, `NSPasteboard`, then Messages.app | Apple's supported edit window is five edits within 15 minutes. Direct SMS/MMS/RCS cannot be edited; mixed-protocol groups are eligible when another participant uses iMessage. The local Messages scripting dictionary exposes `send` but no edit command, so i2Message never writes private Messages state. | Compare the original and replacement, see the live edit deadline and remaining edits, then continue through the three-step Messages handoff. Fixture mode updates locally and preserves edit history. | `AppViewModelTests.testFixtureOutgoingMessageEditUpdatesTextAndKeepsHistory`, `testLiveMessageEditReadinessExpiresWhileEditorIsOpen`, live handoff and restriction tests |
| Send attachment to one-recipient iMessage | Implemented with permission | Messages.app Apple Events `send POSIX file ...` | Requires readable local file, Automation permission, and configured size limit. | For unsupported service/group cases, copy/open handoff; for too-large files, show a typed error. | `testAttachmentCommandUsesPOSIXFileWithoutMutatingMessagesStorage`, `testAttachmentSizeIsValidatedBeforeAutomation` |
| Open conversation in Messages.app | Partial handoff | `NSWorkspace` opens Messages.app | Read-only i2Message `ConversationID` values are not public Messages deep-link IDs. Exact transcript selection is not guaranteed. | Open Messages.app and copy conversation title/handles/draft to pasteboard. | `testOpenConversationUsesHandoffInsteadOfPrivateMutation` |
| Contact handoff | Partial handoff | Contacts.app if available, otherwise Messages.app | Exact contact-card deep linking is not a stable public API for every CNContact source. | Copy contact summary to pasteboard and open Contacts.app or Messages.app. | Covered by protocol boundary; real app smoke checked manually |
| Notification hooks | Implemented hook | `UNUserNotificationCenter` | This does not observe Messages by itself; it lets the read-only observer post local notifications after permission. | Show permission status and System Settings recovery. | `PermissionStateMappingTests` |
| Paste handoff | Implemented | `NSPasteboard` text and file URLs | User explicitly completes the send in Messages.app. | None needed. | `testOpenConversationUsesHandoffInsteadOfPrivateMutation` exercises handoff path |
| Drag-and-drop handoff | Implemented payload model | `MessagingHandoffItem` payloads | UI can convert payloads to native drag items without touching Messages internals. | Paste/open handoff remains available. | Service protocol tests |
| Mark read / unread | Unsupported, graceful | None | Mark-read is a Messages state mutation without a supported public automation API. Direct `chat.db` writes are forbidden. | Open the conversation in Messages.app and let Apple's client update read state. | `SafeMessagingActionServiceTests.testMarkReadIsExplicitlyUnsupported` |
| Tapbacks, undo send, delete, pin, mute | Unsupported for now | None | These are Apple-private Messages mutations or UI-only affordances without stable public automation contracts. | Open Messages.app for the native action. | Matrix documentation; add tests when a supported API appears |

## Permission Plumbing

| Permission | Used for | Request/check behavior |
| --- | --- | --- |
| Full Disk Access | Read-only Messages history workers | Detected by readability of the standard Messages database path; opened in System Settings because macOS has no programmatic grant prompt. |
| Contacts | Names, avatars, contact handoff | Requested through `CNContactStore`; mapped to shared `PermissionStatus`. |
| Messages Automation | Sends and preflight | Requested by running a harmless `count services` Apple Event against Messages.app so TCC attributes permission to i2Message. |
| Notifications | Local message notifications | Requested through `UNUserNotificationCenter`; mapped through `PermissionStateMapper`. |

## Manual QA Checklist

Run automated verification first:

```sh
./scripts/generate-xcodeproj.sh
./scripts/test.sh
./scripts/build.sh
```

Then validate real macOS behavior on a Mac signed into Messages.app:

1. Launch i2Message, open the sidebar footer, and verify Full Disk Access, Contacts, Messages Automation, and Notifications show explicit states.
2. Request Contacts permission. Confirm System Settings and the app agree on the resulting state.
3. Request Notifications permission. Confirm the app reports granted or denied without crashing.
4. Request Messages Automation. Confirm macOS prompts for i2Message to control Messages.app, not Terminal or `osascript`.
5. With Automation granted and Messages.app signed into iMessage, send a short text to a test iMessage recipient from a one-recipient mock thread. Confirm the message appears in Messages.app before considering it sent.
6. Attach a small local file in a development branch or test harness that creates a `DraftAttachment`, send to the same iMessage recipient, and confirm the file appears in Messages.app.
7. Try an oversized attachment over the configured 100 MB default. Confirm i2Message shows the typed size error and does not run Apple Events.
8. Try an SMS/MMS/RCS recipient. Confirm i2Message does not claim direct success, copies the draft, and opens Messages.app for manual send.
9. Try a group conversation. Confirm i2Message uses handoff rather than sending separate direct messages.
10. Try reply, mark-read, tapback, edit, delete, pin, and mute affordances as they are introduced in UI. Confirm each unsupported action shows the documented handoff/unavailable state.
11. Sign and notarize a release archive, then repeat Automation request and one real iMessage send from the notarized app. Confirm TCC shows the signed i2Message app and the send still routes through Messages.app.

## Diagnostics Expectations

- Error text must not include message bodies, phone numbers, email addresses, contact names, or raw attachment paths in logs.
- User-facing errors should distinguish Automation denied, Messages.app unavailable, Messages.app not signed in, unreachable recipient, unsupported service, and attachment too large.
- Receipts from AppleScript sends intentionally leave `messageID` nil because macOS does not return a stable public Messages ID.

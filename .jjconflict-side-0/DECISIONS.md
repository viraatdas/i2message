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

## n3: Added safe Messages action and macOS integration contracts
- **Did:** Added messaging action availability/status models, typed MessagingActionError cases, AppleScript command construction, safe send/start/reply/open/handoff/mark-read service behavior, macOS Automation/Contacts/Notifications/NSWorkspace/NSPasteboard adapters, UI plumbing for permission/parity status and handoff fallback, focused CI-safe tests, and docs/parity.md with manual QA.
- **Interfaces:** Sources/i2MessageCore/MessagingActions/* exposes MessagingActionServicing, MessagingActionAvailabilitySnapshot, MessagingActionKind, MessagingActionResult, MessagingActionPolicy, MessagesAppleScriptCommandBuilder, MessagesAutomationControlling, MessagesHandoffControlling, DraftAttachmentInspecting, MessagingNotificationHooking, and SafeMessagingActionService; Sources/i2MessageCore/SystemIntegration/* exposes MacOSMessagesAutomationController, MacOSMessagesHandoffController, MacOSPermissionManager, MacOSNotificationHook, and PermissionStateMapper; Sources/i2MessageApp/Integration/AppIntegrationEnvironment.swift wires live adapters into the mock app.
- **Follow-ups:**
  - Real-send QA on signed/notarized app [out of lane] — Apple Events sends and attachment sends require a Messages-signed-in Mac and TCC prompts, so CI tests cover command construction/fallbacks only.
  - Hook live attachment picker into composer [out of lane] — Core supports DraftAttachment validation/sending and paste/drag handoff, but the current app composer keeps attach disabled until the UI lane adds picker/drop handling.
- **By:** n3 · 2026-07-04T02:05:30Z

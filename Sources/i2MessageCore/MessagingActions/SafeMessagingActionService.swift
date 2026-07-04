import Foundation

public actor SafeMessagingActionService: MessagingActionServicing {
    private let automation: any MessagesAutomationControlling
    private let handoff: any MessagesHandoffControlling
    private let permissionManager: any PermissionManaging
    private let attachmentInspector: any DraftAttachmentInspecting
    private let policy: MessagingActionPolicy
    private let dateProvider: @Sendable () -> Date
    private let idProvider: @Sendable () -> String

    public init(
        automation: any MessagesAutomationControlling,
        handoff: any MessagesHandoffControlling,
        permissionManager: any PermissionManaging,
        attachmentInspector: any DraftAttachmentInspecting = LocalDraftAttachmentInspector(),
        policy: MessagingActionPolicy = MessagingActionPolicy(),
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        idProvider: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.automation = automation
        self.handoff = handoff
        self.permissionManager = permissionManager
        self.attachmentInspector = attachmentInspector
        self.policy = policy
        self.dateProvider = dateProvider
        self.idProvider = idProvider
    }

    public func availabilitySnapshot() async -> MessagingActionAvailabilitySnapshot {
        let checkedAt = dateProvider()
        let permissions = await permissionManager.permissionSnapshot()
        let messagesAvailable = await automation.isMessagesAvailable()
        let appleEventsState = permissions.status(for: .appleEventsMessages)?.state ?? .notDetermined
        let contactsState = permissions.status(for: .contacts)?.state ?? .notDetermined
        let notificationState = permissions.status(for: .notifications)?.state ?? .notDetermined

        let openFallback = MessagingFallback(
            title: "Open Messages",
            message: "Complete this action in Messages.app. i2Message will not write to private Messages storage.",
            actionLabel: "Open Messages"
        )

        let directSendState = directAutomationState(
            permissionState: appleEventsState,
            messagesAvailable: messagesAvailable
        )

        return MessagingActionAvailabilitySnapshot(
            statuses: [
                MessagingActionAvailability(
                    kind: .sendMessage,
                    state: directSendState,
                    requiredPermissions: directSendState == .requiresPermission ? [.appleEventsMessages] : [],
                    reason: directAutomationReason(state: directSendState),
                    fallback: directSendState == .available ? nil : openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .replyToMessage,
                    state: .unsupported,
                    reason: "Messages AppleScript cannot address a specific reply bubble or thread anchor.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .startConversation,
                    state: directSendState,
                    requiredPermissions: directSendState == .requiresPermission ? [.appleEventsMessages] : [],
                    reason: directSendState == .available
                        ? "Single-recipient iMessage starts can be sent through Messages Automation."
                        : directAutomationReason(state: directSendState),
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .sendAttachment,
                    state: directSendState,
                    requiredPermissions: directSendState == .requiresPermission ? [.appleEventsMessages] : [],
                    reason: directSendState == .available
                        ? "Local attachment files can be sent to a single iMessage recipient through Messages Automation."
                        : directAutomationReason(state: directSendState),
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .openInMessages,
                    state: messagesAvailable ? .requiresUserHandoff : .unavailable,
                    reason: messagesAvailable
                        ? "i2Message can open Messages.app, but macOS does not expose stable deep links for read-only conversation IDs."
                        : "Messages.app could not be found on this Mac.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .contactHandoff,
                    state: permissionBackedState(contactsState),
                    requiredPermissions: contactsState == .notDetermined ? [.contacts] : [],
                    reason: permissionBackedReason(contactsState, granted: "Contacts are available for handoff."),
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .notificationHook,
                    state: permissionBackedState(notificationState),
                    requiredPermissions: notificationState == .notDetermined ? [.notifications] : [],
                    reason: permissionBackedReason(notificationState, granted: "Notifications can be posted for observed incoming messages."),
                    fallback: nil,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .pasteHandoff,
                    state: .available,
                    reason: "Draft text and attachment URLs can be copied to the pasteboard for explicit user handoff.",
                    fallback: nil,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .dragAndDropHandoff,
                    state: .available,
                    reason: "Draft text and local attachment URLs can be represented as drag payloads.",
                    fallback: nil,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .markRead,
                    state: .unsupported,
                    reason: "macOS does not expose a supported mark-read mutation API, and direct chat.db writes are forbidden.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                )
            ],
            checkedAt: checkedAt
        )
    }

    public func validate(_ draft: MessageDraft) async throws -> SendOperation {
        _ = try MessagesAppleScriptCommandBuilder.sendCommand(for: draft, policy: policy)
        try await inspectAttachments(draft.attachments)

        let operationID = idProvider()
        let checkedAt = dateProvider()
        let permissions = await permissionManager.permissionSnapshot()
        let appleEventsState = permissions.status(for: .appleEventsMessages)?.state ?? .notDetermined

        switch appleEventsState {
        case .granted:
            return SendOperation(
                id: operationID,
                draft: draft,
                state: .validating,
                createdAt: checkedAt,
                updatedAt: checkedAt
            )
        case .notDetermined:
            return SendOperation(
                id: operationID,
                draft: draft,
                state: .awaitingPermission,
                createdAt: checkedAt,
                updatedAt: checkedAt,
                failureReason: "Messages Automation permission has not been granted yet."
            )
        case .denied, .restricted:
            throw MessagingActionError.appleEventsDisabled(
                reason: "macOS denied i2Message permission to control Messages.app."
            )
        case .unsupported:
            throw MessagingActionError.unsupportedCapability(
                kind: .sendMessage,
                reason: "Messages Automation is unavailable on this Mac.",
                fallback: "Open Messages.app and send manually."
            )
        }
    }

    public func send(_ draft: MessageDraft) async throws -> SendReceipt {
        let operation = try await validate(draft)
        guard operation.state == .validating else {
            throw MessagingActionError.permissionRequired(
                .appleEventsMessages,
                reason: operation.failureReason ?? "Messages Automation must be approved before i2Message can send."
            )
        }

        let command = try MessagesAppleScriptCommandBuilder.sendCommand(for: draft, policy: policy)
        do {
            _ = try await automation.execute(command)
        } catch let failure as MessagesAutomationFailure {
            throw mapAutomationFailure(failure, draft: draft)
        } catch {
            throw MessagingActionError.automationFailed(reason: error.localizedDescription)
        }

        return SendReceipt(
            operationID: operation.id,
            conversationID: draft.target.conversationID,
            messageID: nil,
            sentAt: dateProvider()
        )
    }

    public func startConversation(_ draft: MessageDraft) async throws -> SendReceipt {
        try await send(draft)
    }

    public func reply(_ draft: MessageDraft, to messageID: MessageID) async throws -> SendReceipt {
        var replyDraft = draft
        replyDraft.replyToMessageID = messageID
        return try await send(replyDraft)
    }

    public func openConversation(_ request: ConversationHandoffRequest) async throws -> MessagingActionResult {
        do {
            try await handoff.openMessages(with: request)
            return MessagingActionResult(
                id: idProvider(),
                kind: .openInMessages,
                outcome: .handedOff,
                completedAt: dateProvider(),
                userMessage: "Opened Messages.app for handoff."
            )
        } catch {
            throw MessagingActionError.handoffFailed(reason: error.localizedDescription)
        }
    }

    public func handoffContact(_ request: ContactHandoffRequest) async throws -> MessagingActionResult {
        do {
            try await handoff.openContact(with: request)
            return MessagingActionResult(
                id: idProvider(),
                kind: .contactHandoff,
                outcome: .handedOff,
                completedAt: dateProvider(),
                userMessage: "Opened the contact handoff target."
            )
        } catch {
            throw MessagingActionError.handoffFailed(reason: error.localizedDescription)
        }
    }

    public func preparePasteHandoff(_ request: PasteHandoffRequest) async throws -> MessagingActionResult {
        try await inspectAttachments(request.attachments)
        do {
            try await handoff.copyToPasteboard(request)
            return MessagingActionResult(
                id: idProvider(),
                kind: .pasteHandoff,
                outcome: .completed,
                completedAt: dateProvider(),
                userMessage: "Copied draft content to the pasteboard."
            )
        } catch {
            throw MessagingActionError.handoffFailed(reason: error.localizedDescription)
        }
    }

    public func dragItems(for request: DragHandoffRequest) async throws -> [MessagingHandoffItem] {
        try await inspectAttachments(request.attachments)
        return try await handoff.dragItems(for: request)
    }

    public func markRead(_ request: MarkReadRequest) async throws -> MessagingActionResult {
        throw MessagingActionError.unsupportedCapability(
            kind: .markRead,
            reason: "No supported Messages.app automation API can mark the selected conversation read.",
            fallback: "Open the conversation in Messages.app to let Apple's client update read state."
        )
    }

    private func inspectAttachments(_ attachments: [DraftAttachment]) async throws {
        for attachment in attachments {
            guard await attachmentInspector.fileExists(at: attachment.fileURL) else {
                throw MessagingActionError.validationFailed(
                    field: "attachment",
                    reason: "\(attachment.filename) is not readable at its selected location."
                )
            }

            guard let byteCount = try await attachmentInspector.byteCount(for: attachment.fileURL) else {
                continue
            }

            if byteCount > policy.maxAttachmentByteCount {
                throw MessagingActionError.attachmentTooLarge(
                    filename: attachment.filename,
                    byteCount: byteCount,
                    maxByteCount: policy.maxAttachmentByteCount
                )
            }
        }
    }

    private func directAutomationState(
        permissionState: PermissionState,
        messagesAvailable: Bool
    ) -> MessagingActionAvailabilityState {
        guard messagesAvailable else {
            return .unavailable
        }

        switch permissionState {
        case .granted:
            return .available
        case .notDetermined:
            return .requiresPermission
        case .denied, .restricted:
            return .unavailable
        case .unsupported:
            return .unsupported
        }
    }

    private func directAutomationReason(state: MessagingActionAvailabilityState) -> String {
        switch state {
        case .available:
            return "Messages Automation is available for single-recipient iMessage sends."
        case .requiresPermission:
            return "Messages Automation permission is required before i2Message can send."
        case .unavailable:
            return "Messages.app is missing or Automation permission was denied."
        case .unsupported:
            return "Messages Automation is unsupported on this Mac."
        case .requiresUserHandoff, .degraded:
            return "Messages.app handoff is required."
        }
    }

    private func permissionBackedState(_ state: PermissionState) -> MessagingActionAvailabilityState {
        switch state {
        case .granted:
            return .available
        case .notDetermined:
            return .requiresPermission
        case .denied, .restricted:
            return .unavailable
        case .unsupported:
            return .unsupported
        }
    }

    private func permissionBackedReason(_ state: PermissionState, granted: String) -> String {
        switch state {
        case .granted:
            return granted
        case .notDetermined:
            return "Permission has not been requested yet."
        case .denied:
            return "Permission was denied in System Settings."
        case .restricted:
            return "Permission is restricted by macOS policy."
        case .unsupported:
            return "This permission is unsupported on the current platform."
        }
    }

    private func mapAutomationFailure(
        _ failure: MessagesAutomationFailure,
        draft: MessageDraft
    ) -> MessagingActionError {
        switch failure.kind {
        case .appleEventsDenied:
            return .appleEventsDisabled(reason: failure.reason)
        case .appUnavailable:
            return .messagesAppUnavailable(reason: failure.reason)
        case .notSignedIn:
            return .messagesAppNotSignedIn(reason: failure.reason)
        case .recipientNotReachable:
            return .recipientNotReachable(
                service: draft.requestedService ?? .iMessage,
                reason: failure.reason
            )
        case .scriptFailed:
            return .automationFailed(reason: failure.reason)
        }
    }
}

public struct LocalDraftAttachmentInspector: DraftAttachmentInspecting {
    public init() {}

    public func fileExists(at fileURL: URL) async -> Bool {
        guard fileURL.isFileURL else {
            return false
        }
        return FileManager.default.isReadableFile(atPath: fileURL.path)
    }

    public func byteCount(for fileURL: URL) async throws -> Int64? {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let number = attributes[.size] as? NSNumber {
            return number.int64Value
        }
        return nil
    }
}

private extension SendTarget {
    var conversationID: ConversationID? {
        if case .existingConversation(let id) = self {
            return id
        }
        return nil
    }
}

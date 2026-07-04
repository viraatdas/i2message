import Combine
import Foundation
import i2MessageCore

@MainActor
final class MockInboxViewModel: ObservableObject {
    @Published var conversations: [Conversation]
    @Published var selectedConversationID: ConversationID?
    @Published var searchText: String = ""
    @Published var semanticSearchEnabled: Bool = false
    @Published var isLoadingConversations: Bool = false
    @Published var isLoadingMessages: Bool = false
    @Published var isSendingDraft: Bool = false
    @Published var draftText: String = ""
    @Published var integrationNotice: String?
    @Published var permissionSnapshot: PermissionSnapshot
    @Published var actionAvailabilitySnapshot: MessagingActionAvailabilitySnapshot

    let contacts: [Contact]

    private let integration: AppIntegrationEnvironment

    init(integration: AppIntegrationEnvironment = .live()) {
        let now = Date()
        self.integration = integration
        self.contacts = MockData.contacts
        self.conversations = MockData.conversations
        self.selectedConversationID = MockData.conversations.first?.id
        self.permissionSnapshot = PermissionSnapshot(
            statuses: [
                PermissionStatus(
                    permission: .fullDiskAccess,
                    state: .notDetermined,
                    reason: "Needed for read-only Messages history access.",
                    lastCheckedAt: now
                ),
                PermissionStatus(
                    permission: .contacts,
                    state: .notDetermined,
                    reason: "Needed for names, avatars, and contact handoff.",
                    lastCheckedAt: now
                ),
                PermissionStatus(
                    permission: .appleEventsMessages,
                    state: .notDetermined,
                    reason: "Needed for supported Messages.app automation.",
                    lastCheckedAt: now
                ),
                PermissionStatus(
                    permission: .notifications,
                    state: .notDetermined,
                    reason: "Needed for local notification hooks.",
                    lastCheckedAt: now
                )
            ]
        )
        self.actionAvailabilitySnapshot = .conservativeDefault(checkedAt: now)
    }

    var filteredConversations: [Conversation] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return conversations
        }

        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(trimmedQuery)
                || conversation.participants.contains { $0.displayName.localizedCaseInsensitiveContains(trimmedQuery) }
                || MockData.messages(for: conversation.id).contains { $0.body.plainText.localizedCaseInsensitiveContains(trimmedQuery) }
        }
    }

    var selectedConversation: Conversation? {
        guard let selectedConversationID else {
            return filteredConversations.first
        }
        return conversations.first { $0.id == selectedConversationID }
    }

    var selectedMessages: [Message] {
        guard let selectedConversation else {
            return []
        }
        return MockData.messages(for: selectedConversation.id)
    }

    var searchResults: [SearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        return MockData.allMessages.compactMap { message in
            guard message.body.plainText.localizedCaseInsensitiveContains(query),
                  let conversation = conversations.first(where: { $0.id == message.conversationID }) else {
                return nil
            }

            return SearchResult(
                id: "result.\(message.id.rawValue)",
                kind: .message,
                conversationID: message.conversationID,
                messageID: message.id,
                contactID: message.senderID,
                title: conversation.title,
                subtitle: senderName(for: message.senderID),
                snippet: message.body.plainText,
                matchedRanges: [],
                score: semanticSearchEnabled ? 0.83 : 1.0,
                date: message.sentAt
            )
        }
    }

    func contact(for id: ContactID?) -> Contact? {
        guard let id else {
            return nil
        }
        return contacts.first { $0.id == id }
    }

    func senderName(for id: ContactID?) -> String {
        contact(for: id)?.displayName ?? "Unknown"
    }

    func selectConversation(_ id: ConversationID) {
        selectedConversationID = id
    }

    func selectNextConversation() {
        moveSelection(offset: 1)
    }

    func selectPreviousConversation() {
        moveSelection(offset: -1)
    }

    func refreshIntegrationStatus() {
        Task {
            await refreshIntegrationStatusNow()
        }
    }

    func requestPermission(_ permission: AppPermission) {
        Task {
            do {
                let status = try await integration.permissionManager.request(permission)
                upsertPermissionStatus(status)
                await refreshIntegrationStatusNow()
            } catch {
                integrationNotice = userFacingMessage(for: error)
            }
        }
    }

    func openSelectedConversationInMessages() {
        guard let conversation = selectedConversation else {
            integrationNotice = "Select a conversation before opening Messages.app."
            return
        }

        Task {
            do {
                let result = try await integration.messagingActions.openConversation(
                    handoffRequest(for: conversation, draftText: "")
                )
                integrationNotice = result.userMessage
            } catch {
                integrationNotice = userFacingMessage(for: error)
            }
        }
    }

    func openNewConversationHandoff() {
        Task {
            do {
                let result = try await integration.messagingActions.openConversation(
                    ConversationHandoffRequest(displayTitle: "New Message")
                )
                integrationNotice = result.userMessage
            } catch {
                integrationNotice = userFacingMessage(for: error)
            }
        }
    }

    func sendDraftInSelectedConversation() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        guard let conversation = selectedConversation else {
            integrationNotice = "Select a conversation before sending."
            return
        }

        let draft = MessageDraft(
            target: .handles(handles(for: conversation)),
            text: draftText,
            requestedService: conversation.service
        )

        isSendingDraft = true
        Task {
            defer { isSendingDraft = false }

            do {
                _ = try await integration.messagingActions.send(draft)
                draftText = ""
                integrationNotice = "Message sent through Messages.app."
                await refreshIntegrationStatusNow()
            } catch {
                await fallbackToMessagesHandoff(
                    error: error,
                    conversation: conversation,
                    draftText: draft.text
                )
            }
        }
    }

    private func moveSelection(offset: Int) {
        let visibleConversations = filteredConversations
        guard !visibleConversations.isEmpty else {
            selectedConversationID = nil
            return
        }

        let currentIndex = selectedConversationID.flatMap { selectedID in
            visibleConversations.firstIndex { $0.id == selectedID }
        } ?? 0

        let nextIndex = min(max(currentIndex + offset, 0), visibleConversations.count - 1)
        selectedConversationID = visibleConversations[nextIndex].id
    }

    private func refreshIntegrationStatusNow() async {
        permissionSnapshot = await integration.permissionManager.permissionSnapshot()
        actionAvailabilitySnapshot = await integration.messagingActions.availabilitySnapshot()
    }

    private func fallbackToMessagesHandoff(
        error: Error,
        conversation: Conversation,
        draftText: String
    ) async {
        guard shouldOfferHandoff(for: error) else {
            integrationNotice = userFacingMessage(for: error)
            return
        }

        do {
            _ = try await integration.messagingActions.preparePasteHandoff(
                PasteHandoffRequest(text: draftText)
            )
            _ = try await integration.messagingActions.openConversation(
                handoffRequest(for: conversation, draftText: draftText)
            )
            integrationNotice = "\(userFacingMessage(for: error)) Draft copied and Messages.app opened for manual send."
        } catch {
            integrationNotice = userFacingMessage(for: error)
        }
    }

    private func shouldOfferHandoff(for error: Error) -> Bool {
        guard let actionError = error as? MessagingActionError else {
            return false
        }

        switch actionError {
        case .permissionRequired,
             .appleEventsDisabled,
             .messagesAppNotSignedIn,
             .recipientNotReachable,
             .serviceUnavailable,
             .unsupportedCapability,
             .automationFailed:
            return true
        case .messagesAppUnavailable,
             .attachmentTooLarge,
             .validationFailed,
             .handoffFailed:
            return false
        }
    }

    private func handoffRequest(for conversation: Conversation, draftText: String) -> ConversationHandoffRequest {
        ConversationHandoffRequest(
            conversationID: conversation.id,
            displayTitle: conversation.title,
            handles: handles(for: conversation),
            draftText: draftText
        )
    }

    private func handles(for conversation: Conversation) -> [ContactHandle] {
        conversation.participants
            .filter { !$0.isCurrentUser }
            .flatMap(\.handles)
    }

    private func upsertPermissionStatus(_ status: PermissionStatus) {
        var statuses = permissionSnapshot.statuses
        if let index = statuses.firstIndex(where: { $0.permission == status.permission }) {
            statuses[index] = status
        } else {
            statuses.append(status)
        }
        permissionSnapshot = PermissionSnapshot(statuses: statuses)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError {
            let description = localizedError.errorDescription ?? error.localizedDescription
            if let suggestion = localizedError.recoverySuggestion {
                return "\(description) \(suggestion)"
            }
            return description
        }

        return error.localizedDescription
    }
}

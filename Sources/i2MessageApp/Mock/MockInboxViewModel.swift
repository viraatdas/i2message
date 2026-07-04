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
    @Published var permissionSnapshot: PermissionSnapshot

    let contacts: [Contact]

    init() {
        self.contacts = MockData.contacts
        self.conversations = MockData.conversations
        self.selectedConversationID = MockData.conversations.first?.id
        self.permissionSnapshot = PermissionSnapshot(
            statuses: [
                PermissionStatus(
                    permission: .fullDiskAccess,
                    state: .notDetermined,
                    reason: "Needed for read-only Messages history access.",
                    lastCheckedAt: Date()
                ),
                PermissionStatus(
                    permission: .appleEventsMessages,
                    state: .notDetermined,
                    reason: "Needed for future supported send automation.",
                    lastCheckedAt: Date()
                )
            ]
        )
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
}

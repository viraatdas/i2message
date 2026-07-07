import Foundation
import i2MessageCore

enum SidebarDestination: String, CaseIterable, Identifiable {
    case conversations
    case contacts
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversations:
            return "Messages"
        case .contacts:
            return "Contacts"
        case .search:
            return "Search"
        }
    }

    var symbolName: String {
        switch self {
        case .conversations:
            return "message"
        case .contacts:
            return "person.2"
        case .search:
            return "magnifyingglass"
        }
    }
}

enum SidebarDisplayMode: String, CaseIterable {
    case full
    case compact
    case hidden

    var next: SidebarDisplayMode {
        switch self {
        case .full:
            return .compact
        case .compact:
            return .hidden
        case .hidden:
            return .full
        }
    }
}

enum ConversationScope: String, CaseIterable, Identifiable {
    case all
    case unread
    case pinned
    case muted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .unread:
            return "Unread"
        case .pinned:
            return "Pinned"
        case .muted:
            return "Muted"
        }
    }
}

enum UIContentPhase: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

enum FocusRequest: Equatable {
    case sidebarSearch
    case searchField
    case composer
    case commandPalette
    case newMessageRecipient
}

/// A conversation staged by Cmd+N that has no row in Messages yet; the first
/// sent message is addressed to `handles` and creates the real thread.
struct PendingNewConversation: Equatable {
    var conversation: Conversation
    var handles: [ContactHandle]
}

/// A link discovered inside a conversation's messages, shown in the Cmd+I info panel.
struct SharedLink: Identifiable, Equatable {
    var url: URL
    var sentAt: Date
    var id: String { url.absoluteString }

    var displayTitle: String {
        url.host.map { host in
            host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } ?? url.absoluteString
    }
}

struct StatusBanner: Identifiable, Equatable {
    enum Tone: String, Equatable {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    var tone: Tone
    var title: String
    var message: String
    var actionTitle: String?
}

struct TranscriptPageState: Equatable {
    var messages: [Message]
    var olderCursor: PageCursor?
    var hasMoreOlder: Bool
    var isLoadingOlder: Bool
    var phase: UIContentPhase
    var totalCount: Int?
    var errorMessage: String?
    var usesFixtureData = false

    static let empty = TranscriptPageState(
        messages: [],
        olderCursor: nil,
        hasMoreOlder: false,
        isLoadingOlder: false,
        phase: .idle,
        totalCount: nil,
        errorMessage: nil
    )
}

struct IndexingProgress: Equatable {
    var isIndexing: Bool
    var exactProgress: Double
    var semanticProgress: Double
    var lastIndexedAt: Date?
    var message: String

    static let idle = IndexingProgress(
        isIndexing: false,
        exactProgress: 1,
        semanticProgress: 0.68,
        lastIndexedAt: Date(timeIntervalSinceReferenceDate: 805_000_000),
        message: "Semantic index warming locally"
    )
}

enum AppCommand: String, CaseIterable, Identifiable {
    case newMessage
    case openSearch
    case searchCurrentChat
    case toggleSemantic
    case nextConversation
    case previousConversation
    case openSettings
    case rebuildIndexes
    case toggleOffline
    case simulateError
    case clearBanner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newMessage:
            return "New Message"
        case .openSearch:
            return "Search All Chats"
        case .searchCurrentChat:
            return "Search This Chat"
        case .toggleSemantic:
            return "Toggle Semantic Search"
        case .nextConversation:
            return "Next Conversation"
        case .previousConversation:
            return "Previous Conversation"
        case .openSettings:
            return "Open Settings"
        case .rebuildIndexes:
            return "Rebuild Local Indexes"
        case .toggleOffline:
            return "Toggle Offline Mode"
        case .simulateError:
            return "Show Mock Error"
        case .clearBanner:
            return "Dismiss Banner"
        }
    }

    var subtitle: String {
        switch self {
        case .newMessage:
            return "Start or hand off a new Messages draft"
        case .openSearch:
            return "Search every conversation at once"
        case .searchCurrentChat:
            return "Search only the selected conversation"
        case .toggleSemantic:
            return "Switch between phrase search and local meaning search"
        case .nextConversation, .previousConversation:
            return "Keyboard-first conversation navigation"
        case .openSettings:
            return "Permissions, privacy, indexing, and appearance"
        case .rebuildIndexes:
            return "Show local index progress states"
        case .toggleOffline:
            return "Preview unavailable data and local-cache UI"
        case .simulateError:
            return "Preview a recoverable error banner"
        case .clearBanner:
            return "Clear the active status banner"
        }
    }

    var symbolName: String {
        switch self {
        case .newMessage:
            return "square.and.pencil"
        case .openSearch:
            return "magnifyingglass"
        case .searchCurrentChat:
            return "text.magnifyingglass"
        case .toggleSemantic:
            return "sparkles"
        case .nextConversation:
            return "arrow.down"
        case .previousConversation:
            return "arrow.up"
        case .openSettings:
            return "gearshape"
        case .rebuildIndexes:
            return "arrow.clockwise"
        case .toggleOffline:
            return "wifi.slash"
        case .simulateError:
            return "exclamationmark.triangle"
        case .clearBanner:
            return "xmark.circle"
        }
    }

    var shortcutText: String? {
        switch self {
        case .newMessage:
            return "⌘N"
        case .openSearch:
            return "⌘⇧P"
        case .searchCurrentChat:
            return "⌘F"
        case .toggleSemantic:
            return "⌘⇧K"
        case .nextConversation:
            return "⌘↓"
        case .previousConversation:
            return "⌘↑"
        case .openSettings:
            return "⌘,"
        case .rebuildIndexes, .toggleOffline, .simulateError, .clearBanner:
            return nil
        }
    }
}

import SwiftUI
import i2MessageCore

struct SidebarView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Group {
            if model.sidebarMode == .compact {
                compactRail
            } else {
                fullSidebar
            }
        }
        .background(I2Palette.sidebarBackground)
        .accessibilityElement(children: .contain)
    }

    // MARK: Full sidebar

    private var fullSidebar: some View {
        VStack(spacing: 0) {
            conversationsList
            footer
        }
    }

    private var conversationsList: some View {
        Group {
            if model.conversationPhase == .loading {
                ConversationSkeletonList()
            } else if model.filteredConversations.isEmpty {
                EmptyStateView(
                    title: "No conversations",
                    message: "Recent conversations appear here.",
                    systemImage: "message"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredConversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == model.selectedConversationID
                            ) {
                                Task { await model.selectConversation(conversation.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Compact rail

    private var compactRail: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(model.filteredConversations) { conversation in
                        CompactConversationButton(
                            conversation: conversation,
                            isSelected: conversation.id == model.selectedConversationID
                        ) {
                            Task { await model.selectConversation(conversation.id) }
                        }
                    }
                }
                .padding(.vertical, 10)
            }

            if needsAttention {
                attentionDot
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer (only surfaces problems)

    @ViewBuilder
    private var footer: some View {
        let pending = attentionPermissions
        if model.isOffline || model.indexingProgress.isIndexing || !pending.isEmpty {
            I2Divider()
            VStack(alignment: .leading, spacing: 6) {
                if model.isOffline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.orange)
                        Text("Offline cache")
                            .font(.caption)
                        Spacer()
                    }
                }

                if model.indexingProgress.isIndexing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Indexing recent chats…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                ForEach(pending) { status in
                    HStack(spacing: 8) {
                        PermissionStateIcon(state: status.state)
                        Text(status.permission.displayName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            Task { await model.requestPermission(status.permission) }
                        } label: {
                            Text("Fix")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .help("Request \(status.permission.displayName)")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }

    private var attentionPermissions: [PermissionStatus] {
        model.permissionSnapshot.statuses.filter { status in
            (status.permission == .fullDiskAccess || status.permission == .contacts)
                && status.state != .granted
        }
    }

    private var needsAttention: Bool {
        !attentionPermissions.isEmpty
    }

    private var attentionDot: some View {
        Button {
            model.isSettingsPresented = true
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
        .buttonStyle(.borderless)
        .help("Permissions need attention")
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                AvatarStack(contacts: conversation.participants.filter { !$0.isCurrentUser }, size: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(conversation.title)
                            .font(.body.weight(conversation.unreadCount > 0 ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if conversation.pinnedRank != nil {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack(spacing: 6) {
                        Text(conversation.lastMessage?.text.isEmpty == false ? conversation.lastMessage!.text : "No messages yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if conversation.unreadCount > 0 {
                            UnreadBadge(count: conversation.unreadCount)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSelected ? I2Palette.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let unread = conversation.unreadCount > 0 ? ", \(conversation.unreadCount) unread" : ""
        return "\(conversation.title), \(conversation.lastMessage?.text ?? "No messages")\(unread)"
    }
}

private struct CompactConversationButton: View {
    let conversation: Conversation
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            AvatarStack(contacts: Array(conversation.participants.filter { !$0.isCurrentUser }.prefix(1)), size: 36)
                .overlay(alignment: .topTrailing) {
                    if conversation.unreadCount > 0 {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                            .offset(x: 2, y: -2)
                    }
                }
                .padding(5)
                .background(isSelected ? I2Palette.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(conversation.title)
        .accessibilityLabel(conversation.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

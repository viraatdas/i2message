import SwiftUI
import i2MessageCore

struct SidebarView: View {
    @EnvironmentObject private var model: MockInboxViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.isLoadingConversations {
                ConversationSkeletonList()
            } else if model.filteredConversations.isEmpty {
                EmptyStateView(
                    title: "No matches",
                    message: "Try a different contact, phrase, or attachment name.",
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                List(selection: $model.selectedConversationID) {
                    ForEach(model.filteredConversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(conversation.id)
                            .accessibilityAddTraits(conversation.id == model.selectedConversationID ? .isSelected : [])
                    }
                }
                .listStyle(.sidebar)
            }

            PermissionFooter(snapshot: model.permissionSnapshot)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Messages")
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Spacer()

            Text("\(model.conversations.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("\(model.conversations.count) conversations")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(contact: conversation.participants.first { !$0.isCurrentUser })
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if conversation.pinnedRank != nil {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }

                    if conversation.isMuted {
                        Image(systemName: "bell.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Muted")
                    }

                    Spacer(minLength: 8)

                    Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(conversation.lastMessage?.text ?? "No messages yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(conversation.service.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    if conversation.unreadCount > 0 {
                        UnreadBadge(count: conversation.unreadCount)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let unread = conversation.unreadCount > 0 ? ", \(conversation.unreadCount) unread" : ""
        return "\(conversation.title), \(conversation.lastMessage?.text ?? "No messages")\(unread)"
    }
}

struct PermissionFooter: View {
    let snapshot: PermissionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(snapshot.statuses) { status in
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: status.state))
                        .foregroundStyle(color(for: status.state))
                        .frame(width: 16)

                    Text(label(for: status.permission))
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text(status.state.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func iconName(for state: PermissionState) -> String {
        switch state {
        case .granted:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "exclamationmark.triangle.fill"
        case .notDetermined:
            return "circle.dashed"
        case .unsupported:
            return "slash.circle"
        }
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .granted:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .secondary
        case .unsupported:
            return .orange
        }
    }

    private func label(for permission: AppPermission) -> String {
        switch permission {
        case .fullDiskAccess:
            return "Full Disk Access"
        case .contacts:
            return "Contacts"
        case .appleEventsMessages:
            return "Messages Automation"
        case .notifications:
            return "Notifications"
        }
    }
}

import SwiftUI
import i2MessageCore

struct ConversationDetailView: View {
    @EnvironmentObject private var model: MockInboxViewModel

    var body: some View {
        Group {
            if let conversation = model.selectedConversation {
                VStack(spacing: 0) {
                    ConversationHeader(conversation: conversation)

                    Divider()

                    if model.isLoadingMessages {
                        MessageSkeletonList()
                    } else {
                        TranscriptView(
                            conversation: conversation,
                            messages: model.selectedMessages
                        )
                    }

                    Divider()

                    MockComposer(conversation: conversation)
                }
            } else {
                EmptyStateView(
                    title: "Select a conversation",
                    message: "Conversation history and search results will appear here.",
                    systemImage: "message"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
    }
}

struct ConversationHeader: View {
    @EnvironmentObject private var model: MockInboxViewModel

    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                AvatarStack(contacts: conversation.participants.filter { !$0.isCurrentUser })

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(participantSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {} label: {
                    Label("Conversation Details", systemImage: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Conversation Details")
                .accessibilityLabel("Conversation details")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SearchSummaryBar()
            }
        }
    }

    private var participantSummary: String {
        let names = conversation.participants
            .filter { !$0.isCurrentUser }
            .map(\.displayName)

        if names.isEmpty {
            return conversation.service.rawValue
        }

        return names.joined(separator: ", ")
    }
}

struct SearchSummaryBar: View {
    @EnvironmentObject private var model: MockInboxViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.semanticSearchEnabled ? "sparkles" : "magnifyingglass")
                .foregroundStyle(.secondary)

            Text(model.semanticSearchEnabled ? "Semantic" : "Exact")
                .font(.callout.weight(.semibold))

            Text("\(model.searchResults.count) results")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button(model.semanticSearchEnabled ? "Exact" : "Semantic") {
                model.semanticSearchEnabled.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .accessibilityElement(children: .combine)
    }
}

struct TranscriptView: View {
    @EnvironmentObject private var model: MockInboxViewModel

    let conversation: Conversation
    let messages: [Message]

    var body: some View {
        if messages.isEmpty {
            EmptyStateView(
                title: "No messages",
                message: "This thread has no mock transcript yet.",
                systemImage: "text.bubble"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        LoadMoreMessagesButton()

                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                sender: model.contact(for: message.senderID)
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    if let lastID = messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct LoadMoreMessagesButton: View {
    var body: some View {
        HStack {
            Spacer()
            Button {
            } label: {
                Label("Load Earlier", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
            .accessibilityLabel("Load earlier messages unavailable in mock mode")
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

struct MessageBubble: View {
    let message: Message
    let sender: Contact?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.direction == .outgoing {
                Spacer(minLength: 80)
            } else {
                AvatarView(contact: sender, size: 26)
            }

            VStack(alignment: message.direction == .outgoing ? .trailing : .leading, spacing: 4) {
                if message.direction == .incoming {
                    Text(sender?.displayName ?? "Unknown")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !message.body.plainText.isEmpty {
                        Text(message.body.plainText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(message.attachments) { attachment in
                        AttachmentChip(attachment: attachment)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(backgroundStyle)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 560, alignment: message.direction == .outgoing ? .trailing : .leading)

                HStack(spacing: 5) {
                    Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    if message.direction == .outgoing {
                        Text(message.status.rawValue)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: message.direction == .outgoing ? .trailing : .leading)

            if message.direction != .outgoing {
                Spacer(minLength: 80)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var backgroundStyle: Color {
        switch message.direction {
        case .outgoing:
            return Color.accentColor.opacity(0.16)
        case .incoming:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color(nsColor: .windowBackgroundColor)
        }
    }

    private var accessibilityLabel: String {
        let name = sender?.displayName ?? (message.direction == .outgoing ? "You" : "Unknown")
        return "\(name), \(message.body.plainText), \(message.sentAt.formatted(date: .omitted, time: .shortened))"
    }
}

struct AttachmentChip: View {
    let attachment: MessageAttachment

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
            Text(attachment.filename)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attachment \(attachment.filename)")
    }

    private var iconName: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .audio:
            return "waveform"
        case .file:
            return "doc"
        case .sticker:
            return "face.smiling"
        case .tapback:
            return "hand.thumbsup"
        case .unknown:
            return "paperclip"
        }
    }
}

struct MockComposer: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 10) {
            Button {} label: {
                Label("Attach", systemImage: "paperclip")
            }
            .buttonStyle(.borderless)
            .disabled(true)
            .accessibilityLabel("Attach unavailable in mock mode")

            TextField("Message \(conversation.title)", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
                .accessibilityLabel("Message composer unavailable in mock mode")

            Button {} label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .accessibilityLabel("Send unavailable in mock mode")
        }
        .padding(14)
    }
}

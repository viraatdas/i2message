import SwiftUI
import UniformTypeIdentifiers
import i2MessageCore

struct ConversationDetailView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showsInspector = true

    var body: some View {
        Group {
            if let conversation = model.selectedConversation {
                VStack(spacing: 0) {
                    ConversationHeader(conversation: conversation, showsInspector: $showsInspector)
                    I2Divider()

                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            TranscriptView(conversation: conversation)
                            I2Divider()
                            ComposerView(conversation: conversation)
                        }

                        if showsInspector {
                            I2Divider()
                                .frame(width: 1)
                            ConversationInspector(conversation: conversation)
                                .frame(width: I2Layout.inspectorWidth)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            } else {
                EmptyStateView(
                    title: "Select a conversation",
                    message: "Conversation history, attachments, search hits, and composer state will appear here.",
                    systemImage: "message"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(I2Palette.appBackground)
    }
}

private struct ConversationHeader: View {
    @EnvironmentObject private var model: AppViewModel
    let conversation: Conversation
    @Binding var showsInspector: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarStack(contacts: conversation.participants.filter { !$0.isCurrentUser }, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(conversation.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    if conversation.pinnedRank != nil {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(model.contactNames(for: conversation).isEmpty ? conversation.service.rawValue : model.contactNames(for: conversation))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let total = model.selectedTranscriptState.totalCount {
                I2Pill(title: "\(model.selectedMessages.count)/\(total)", systemImage: "text.bubble", tint: .secondary)
            }

            Button {
                model.searchConversationScope = conversation.id
                model.searchQuery = conversation.title
                model.sidebarDestination = .search
                Task { await model.performSearch(reset: true) }
            } label: {
                Label("Search This Thread", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Search this thread")

            Button {
                showsInspector.toggle()
            } label: {
                Label(showsInspector ? "Hide Details" : "Show Details", systemImage: "info.circle")
            }
            .buttonStyle(.borderless)
            .help(showsInspector ? "Hide details" : "Show details")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

private struct TranscriptView: View {
    @EnvironmentObject private var model: AppViewModel
    let conversation: Conversation

    var body: some View {
        let state = model.selectedTranscriptState
        Group {
            switch state.phase {
            case .loading:
                MessageSkeletonList()
            case .empty:
                EmptyStateView(
                    title: "No messages",
                    message: "This thread has no loaded mock transcript yet.",
                    systemImage: "text.bubble"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyStateView(
                    title: "Transcript unavailable",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    actionTitle: "Retry"
                ) {
                    Task { await model.loadSelectedConversation(reset: true) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .idle, .loaded:
                transcriptScroll(messages: model.selectedMessages, state: state)
            }
        }
    }

    private func transcriptScroll(messages: [Message], state: TranscriptPageState) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer()
                        Button {
                            Task { await model.loadOlderMessages() }
                        } label: {
                            if state.isLoadingOlder {
                                Label("Loading Earlier", systemImage: "arrow.up.circle")
                            } else {
                                Label(state.hasMoreOlder ? "Load Earlier" : "Start of Thread", systemImage: state.hasMoreOlder ? "arrow.up.circle" : "checkmark.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!state.hasMoreOlder || state.isLoadingOlder)
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if shouldShowDateDivider(at: index, messages: messages) {
                            DateDivider(date: message.sentAt)
                        }

                        MessageBubble(
                            message: message,
                            sender: model.contact(for: message.senderID),
                            isHighlighted: model.highlightedMessageID == message.id,
                            density: model.settings.transcriptDensity
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollToRelevantMessage(proxy: proxy, messages: messages)
            }
            .onChange(of: model.highlightedMessageID) { _ in
                scrollToRelevantMessage(proxy: proxy, messages: messages)
            }
            .onChange(of: messages.last?.id) { _ in
                scrollToRelevantMessage(proxy: proxy, messages: messages)
            }
        }
    }

    private func scrollToRelevantMessage(proxy: ScrollViewProxy, messages: [Message]) {
        if let highlighted = model.highlightedMessageID {
            proxy.scrollTo(highlighted, anchor: .center)
        } else if let last = messages.last?.id {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    private func shouldShowDateDivider(at index: Int, messages: [Message]) -> Bool {
        guard index > 0 else {
            return true
        }
        return !Calendar.current.isDate(messages[index].sentAt, inSameDayAs: messages[index - 1].sentAt)
    }
}

private struct DateDivider: View {
    let date: Date

    var body: some View {
        HStack {
            Rectangle().fill(I2Palette.separator).frame(height: 1)
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            Rectangle().fill(I2Palette.separator).frame(height: 1)
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

private struct MessageBubble: View {
    let message: Message
    let sender: Contact?
    let isHighlighted: Bool
    let density: TranscriptDensity

    var body: some View {
        if message.direction == .system {
            Text(message.body.plainText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else {
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

                    VStack(alignment: .leading, spacing: bubbleSpacing) {
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
                    .padding(.vertical, density == .compact ? 7 : 9)
                    .background(backgroundStyle)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isHighlighted ? Color.accentColor.opacity(0.85) : Color.clear, lineWidth: 2)
                    }
                    .frame(maxWidth: maxBubbleWidth, alignment: message.direction == .outgoing ? .trailing : .leading)

                    if !message.reactions.isEmpty {
                        ReactionCluster(reactions: message.reactions)
                            .padding(.top, -1)
                    }

                    HStack(spacing: 5) {
                        Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                        if message.isEdited {
                            Text("edited")
                        }
                        if message.direction == .outgoing {
                            Text(message.status.statusLabel)
                                .foregroundStyle(message.status == .failed ? .red : .secondary)
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
    }

    private var bubbleSpacing: CGFloat {
        density == .compact ? 5 : 8
    }

    private var maxBubbleWidth: CGFloat {
        density == .compact ? I2Layout.compactTranscriptMaxBubbleWidth : I2Layout.transcriptMaxBubbleWidth
    }

    private var backgroundStyle: Color {
        switch message.direction {
        case .outgoing:
            return I2Palette.outgoingBubble
        case .incoming:
            return I2Palette.incomingBubble
        case .system:
            return I2Palette.appBackground
        }
    }

    private var accessibilityLabel: String {
        let name = sender?.displayName ?? (message.direction == .outgoing ? "You" : "Unknown")
        return "\(name), \(message.body.plainText), \(message.sentAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct ComposerView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var composerFocused: Bool
    @State private var isDropTargeted = false

    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.currentDraftAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.currentDraftAttachments) { attachment in
                            DraftAttachmentChip(attachment: attachment) {
                                model.removeDraftAttachment(attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            HStack(alignment: .bottom, spacing: 9) {
                Button {
                    model.addMockAttachment()
                } label: {
                    Label("Attach", systemImage: "paperclip")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Attach file")

                ZStack(alignment: .topLeading) {
                    if model.currentDraftText.isEmpty {
                        Text("Message \(conversation.title)")
                            .foregroundStyle(.secondary)
                            .font(.body)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 8)
                    }

                    TextEditor(
                        text: Binding(
                            get: { model.currentDraftText },
                            set: { newValue in
                                model.updateDraftText(newValue)
                            }
                        )
                    )
                    .font(.body)
                    .frame(minHeight: 34, maxHeight: 86)
                    .scrollContentBackground(.hidden)
                    .focused($composerFocused)
                    .accessibilityLabel("Message composer")
                }
                .padding(2)
                .background(isDropTargeted ? I2Palette.selectionFill : I2Palette.incomingBubble, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isDropTargeted ? Color.accentColor : I2Palette.separator, lineWidth: 1)
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                    if !providers.isEmpty {
                        model.addDroppedAttachment(filename: "Dropped File")
                    }
                    return !providers.isEmpty
                }

                Button {
                    Task { await model.sendCurrentDraft() }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .labelStyle(.iconOnly)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canSendCurrentDraft)
                .help("Send")
            }

            HStack(spacing: 8) {
                Text("Local mock composer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let operation = model.sendOperation {
                    I2Pill(title: operation.state.rawValue, systemImage: "paperplane", tint: operation.state == .failed ? .red : .secondary)
                }
                Spacer()
                Text("Command-Return sends")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(I2Palette.appBackground)
        .onChange(of: model.focusRequest) { request in
            guard request == .composer else { return }
            composerFocused = true
            model.consumeFocusRequest(.composer)
        }
    }
}

private struct ConversationInspector: View {
    @EnvironmentObject private var model: AppViewModel
    let conversation: Conversation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    I2SectionLabel(title: "Participants")
                        .padding(.horizontal, -14)
                    ForEach(conversation.participants.filter { !$0.isCurrentUser }) { contact in
                        HStack(spacing: 9) {
                            AvatarView(contact: contact, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.displayName)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(contact.handles.first?.value ?? "No handle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                model.selectContact(contact.id)
                            } label: {
                                Label("Open Contact", systemImage: "person.crop.circle")
                            }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                            .help("Open contact")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    I2SectionLabel(title: "Thread State")
                        .padding(.horizontal, -14)
                    detailRow("Service", conversation.service.rawValue)
                    detailRow("Unread", "\(conversation.unreadCount)")
                    detailRow("Loaded", "\(model.selectedMessages.count) messages")
                    if let total = model.selectedTranscriptState.totalCount {
                        detailRow("Total", "\(total) messages")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    I2SectionLabel(title: "Recent Attachments")
                        .padding(.horizontal, -14)
                    let attachments = model.selectedMessages.flatMap(\.attachments).suffix(4)
                    if attachments.isEmpty {
                        Text("No attachments in the loaded page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(attachments)) { attachment in
                            AttachmentChip(attachment: attachment)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    I2SectionLabel(title: "Privacy")
                        .padding(.horizontal, -14)
                    Label("Read-only data boundary", systemImage: "lock")
                        .font(.caption)
                    Label("Semantic search is local", systemImage: "sparkles")
                        .font(.caption)
                    Label("Message bodies are not logged", systemImage: "eye.slash")
                        .font(.caption)
                }
            }
            .padding(14)
        }
        .background(I2Palette.sidebarBackground)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

private extension MessageDeliveryStatus {
    var statusLabel: String {
        switch self {
        case .draft:
            return "draft"
        case .queued:
            return "queued"
        case .sending:
            return "sending"
        case .sent:
            return "sent"
        case .delivered:
            return "delivered"
        case .read:
            return "read"
        case .failed:
            return "failed"
        case .unknown:
            return "unknown"
        }
    }
}

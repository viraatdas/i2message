import AppKit
import SwiftUI
import UniformTypeIdentifiers
import i2MessageCore

struct ConversationDetailView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Group {
            if let conversation = model.selectedConversation {
                VStack(spacing: 0) {
                    ConversationHeader(conversation: conversation)
                    I2Divider()

                    VStack(spacing: 0) {
                        TranscriptView(conversation: conversation)
                        I2Divider()
                        ComposerView(conversation: conversation)
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

private struct TranscriptView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let conversation: Conversation

    // Two-finger swipe on a bubble opens its thread. Trackpad swipes arrive as
    // scroll-wheel events with a dominant deltaX, so a local event monitor
    // tracks horizontal intent over the hovered message.
    @State private var swipeState = ThreadSwipeGestureState()
    @State private var swipeMonitor: Any?

    var body: some View {
        let state = model.selectedTranscriptState
        Group {
            switch state.phase {
            case .loading:
                MessageSkeletonList()
            case .empty:
                EmptyStateView(
                    title: "No messages",
                    message: "This thread has no loaded transcript yet.",
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
                transcriptScroll(messages: model.visibleTranscriptMessages, state: state)
            }
        }
    }

    private func transcriptScroll(messages: [Message], state: TranscriptPageState) -> some View {
        let messageIDs = messages.map(\.id)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
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
                            density: model.settings.transcriptDensity,
                            isGroupStart: isGroupStart(at: index, messages: messages),
                            isGroupEnd: isGroupEnd(at: index, messages: messages)
                        )
                        .id(message.id)
                        .offset(x: swipeOffset(for: message))
                        .overlay(alignment: message.direction == .outgoing ? .trailing : .leading) {
                            swipeAffordance(for: message)
                        }
                        .onHover { hovering in
                            if hovering {
                                swipeState.setHoveredMessageID(message.id)
                            } else if swipeState.hoveredMessageID == message.id {
                                swipeState.setHoveredMessageID(nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollToRelevantMessage(proxy: proxy, messages: messages)
                installSwipeMonitor()
            }
            .onDisappear {
                removeSwipeMonitor()
                resetSwipeState(animated: false)
            }
            .onChange(of: conversation.id) { _, _ in
                resetSwipeState(animated: false)
            }
            .onChange(of: messageIDs) { _, ids in
                if let hoveredMessageID = swipeState.hoveredMessageID,
                   !ids.contains(hoveredMessageID) {
                    resetSwipeState(animated: false)
                }
            }
            .onChange(of: model.highlightedMessageID) { _, _ in
                scrollToRelevantMessage(proxy: proxy, messages: messages)
            }
            .onChange(of: messages.last?.id) { _, _ in
                scrollToRelevantMessage(proxy: proxy, messages: messages)
            }
        }
    }

    private func swipeOffset(for message: Message) -> CGFloat {
        guard !reduceMotion,
              swipeState.hoveredMessageID == message.id,
              message.direction != .system else {
            return 0
        }
        return swipeState.visualOffset
    }

    /// Thread hint that fades in as the swipe progresses.
    @ViewBuilder
    private func swipeAffordance(for message: Message) -> some View {
        let progress = swipeState.hoveredMessageID == message.id ? swipeState.progress : 0
        if progress > 0.05, message.direction != .system {
            Image(systemName: "arrowshape.turn.up.left.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor.opacity(0.35 + 0.65 * progress))
                .scaleEffect(reduceMotion ? 1 : 0.7 + 0.3 * progress)
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
        }
    }

    private func installSwipeMonitor() {
        guard swipeMonitor == nil else {
            return
        }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleSwipeEvent(event)
        }
    }

    private func removeSwipeMonitor() {
        if let swipeMonitor {
            NSEvent.removeMonitor(swipeMonitor)
        }
        swipeMonitor = nil
    }

    /// Routes trackpad scroll events: vertical deltas pass through untouched;
    /// momentum passes through untouched; horizontal travel over a hovered
    /// bubble becomes the swipe-to-thread gesture after intent is clear.
    private func handleSwipeEvent(_ event: NSEvent) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas else {
            resetSwipeState(animated: false)
            return event
        }

        let phase = ThreadSwipeGestureState.ScrollPhase(event: event)
        var update = ThreadSwipeGestureState.Update.passThrough

        if (phase == .ended || phase == .cancelled || phase == .momentum), swipeState.isTracking {
            withAnimation(I2Motion.swipeReset(reduceMotion: reduceMotion)) {
                update = swipeState.handleScroll(
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY,
                    phase: phase
                )
            }
        } else {
            update = swipeState.handleScroll(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                phase: phase
            )
        }

        if let openedMessageID = update.openedMessageID,
           let message = model.visibleTranscriptMessages.first(where: { $0.id == openedMessageID }),
           message.direction != .system {
            if !reduceMotion {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            model.openThread(for: message)
        }

        return update.shouldConsumeEvent ? nil : event
    }

    private func resetSwipeState(animated: Bool) {
        guard swipeState.isTracking else {
            return
        }

        if animated {
            withAnimation(I2Motion.swipeReset(reduceMotion: reduceMotion)) {
                swipeState.resetGesture()
            }
        } else {
            swipeState.resetGesture()
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

    /// True when this message opens a new Slack-style sender block — the first
    /// message from a person after someone else spoke, a long pause, a new day,
    /// or a message that starts its own reply thread.
    private func isGroupStart(at index: Int, messages: [Message]) -> Bool {
        let message = messages[index]
        guard index > 0 else { return true }
        let previous = messages[index - 1]

        if message.direction == .system || previous.direction == .system { return true }
        if message.replyToMessageID != nil { return true }
        if message.direction != previous.direction { return true }
        if message.senderID != previous.senderID { return true }
        if shouldShowDateDivider(at: index, messages: messages) { return true }
        // Break the block after a gap so bursts stay together but distinct
        // conversations across time don't collapse into one avatar.
        return message.sentAt.timeIntervalSince(previous.sentAt) > 5 * 60
    }

    private func isGroupEnd(at index: Int, messages: [Message]) -> Bool {
        guard index < messages.count - 1 else { return true }
        return isGroupStart(at: index + 1, messages: messages)
    }
}

private extension ThreadSwipeGestureState.ScrollPhase {
    init(event: NSEvent) {
        if event.momentumPhase != [] {
            self = .momentum
        } else if event.phase == .ended {
            self = .ended
        } else if event.phase == .cancelled {
            self = .cancelled
        } else {
            self = .changed
        }
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
    @EnvironmentObject private var model: AppViewModel
    let message: Message
    let sender: Contact?
    let isHighlighted: Bool
    let density: TranscriptDensity
    var isGroupStart: Bool = true
    var isGroupEnd: Bool = true
    @State private var isEditHistoryExpanded = false
    @State private var isCustomReactionPickerPresented = false

    private var isOutgoing: Bool {
        message.direction == .outgoing
    }

    private var isReply: Bool {
        message.replyToMessageID != nil
    }

    var body: some View {
        if message.direction == .system {
            Text(message.body.plainText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else {
            HStack(alignment: .top, spacing: 8) {
                if isOutgoing {
                    Spacer(minLength: 80)
                } else if isGroupStart {
                    AvatarView(contact: sender, size: 26)
                } else {
                    // Keep following messages in a block aligned under the avatar.
                    Color.clear.frame(width: 26, height: 1)
                }

                VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                    if message.direction == .incoming, isGroupStart {
                        Text(sender?.displayName ?? "Unknown")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if message.isDeleted {
                        unsentPlaceholder
                    } else {
                        if isEditHistoryExpanded, !message.editHistory.isEmpty {
                            editHistoryList
                        }

                        if let quoted = model.repliedMessage(for: message) {
                            replyThread(quoted: quoted)
                        } else {
                            bubbleContent
                                .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
                        }
                    }

                    if model.isThreadRoot(message) {
                        ThreadIndicatorChip(
                            count: model.threadReplyCount(for: message),
                            repliers: model.threadReplies(to: message.id).map { model.contact(for: $0.senderID) },
                            lastReplyAt: model.threadReplies(to: message.id).last?.sentAt,
                            hasNewActivity: model.hasUnseenThreadReplies(message)
                        ) {
                            model.openThread(rootID: message.id)
                        }
                        .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
                    }

                    if model.canAddToCalendar, let mention = model.dateMention(in: message) {
                        CalendarSuggestionChip(mention: mention) {
                            Task { await model.addToCalendar(from: message) }
                        }
                        .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
                    }

                    if isGroupEnd {
                        HStack(spacing: 5) {
                            Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                            if message.isEdited {
                                editedLabel
                            }
                            if isOutgoing {
                                Text(deliveryStatusText)
                                    .foregroundStyle(message.status == .failed ? .red : .secondary)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)

                if !isOutgoing {
                    Spacer(minLength: 80)
                }
            }
            .padding(.top, isGroupStart ? 8 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    /// Slack-style reply thread: the quoted parent sits above the reply, joined
    /// by a vertical rail so the relationship reads as one threaded unit.
    @ViewBuilder
    private func replyThread(quoted: Message) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(I2Palette.threadRail)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 5) {
                QuotedReplyView(
                    message: quoted,
                    senderName: model.senderName(for: quoted)
                ) {
                    model.openThread(for: message)
                }

                bubbleContent
            }
        }
        .frame(maxWidth: maxBubbleWidth + 10, alignment: isOutgoing ? .trailing : .leading)
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: bubbleSpacing) {
            if !message.body.plainText.isEmpty {
                Text(message.body.plainText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(message.attachments) { attachment in
                VStack(alignment: .leading, spacing: 3) {
                    InlineAttachmentView(attachment: attachment, maxWidth: maxBubbleWidth)

                    if let description = model.attachmentDescriptions[attachment.id] {
                        Label(description, systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .accessibilityLabel("Image description: \(description)")
                    }
                }
                .task(id: attachment.id) {
                    model.requestAttachmentDescription(for: attachment, in: message)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, density == .compact ? 7 : 9)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderStyle, lineWidth: isHighlighted ? 2 : 1)
        }
        .overlay(alignment: isOutgoing ? .topLeading : .topTrailing) {
            if !message.reactions.isEmpty {
                ReactionCluster(reactions: message.reactions) { model.senderName(for: $0) }
                    .offset(x: isOutgoing ? -10 : 10, y: -11)
            }
        }
        .padding(.top, message.reactions.isEmpty ? 0 : 9)
        .contextMenu {
            Section("Tapback") {
                ForEach(MessageBubble.tapbackKinds, id: \.self) { kind in
                    Button {
                        model.toggleReaction(kind, on: message)
                    } label: {
                        Text("\(ReactionCluster.emoji(for: kind, displayText: nil))  \(ReactionCluster.title(for: kind))")
                    }
                }

                Button {
                    isCustomReactionPickerPresented = true
                } label: {
                    Label("React with Emoji", systemImage: "face.smiling")
                }
            }

            Divider()

            if model.isThreadRoot(message) || message.replyToMessageID != nil {
                Button {
                    model.openThread(for: message)
                } label: {
                    Label("Open Thread", systemImage: "bubble.left.and.text.bubble.right")
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.body.plainText, forType: .string)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
            .disabled(message.body.plainText.isEmpty)

            if model.canAddToCalendar, model.dateMention(in: message) != nil {
                Divider()
                Button {
                    Task { await model.addToCalendar(from: message) }
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
            }
        }
        .popover(isPresented: $isCustomReactionPickerPresented, arrowEdge: .top) {
            EmojiPickerPopover(
                title: "Reaction emoji",
                customPlaceholder: "Paste emoji"
            ) { emoji in
                model.toggleCustomReaction(emoji, on: message)
                isCustomReactionPickerPresented = false
            }
            .frame(width: 276)
        }
    }

    static let tapbackKinds: [MessageReactionKind] = [.loved, .liked, .disliked, .laughed, .emphasized, .questioned]

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

    private var borderStyle: Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.85)
        }
        return isOutgoing ? Color.accentColor.opacity(0.22) : I2Palette.incomingBubbleBorder
    }

    private var accessibilityLabel: String {
        let name = sender?.displayName ?? (message.direction == .outgoing ? "You" : "Unknown")
        if message.isDeleted {
            return "\(name) unsent a message"
        }
        return "\(name), \(message.body.plainText), \(message.sentAt.formatted(date: .omitted, time: .shortened))"
    }

    /// iMessage-style retraction placeholder: a dashed, empty bubble.
    private var unsentPlaceholder: some View {
        Text(isOutgoing ? "You unsent a message." : "\(sender?.displayName ?? "They") unsent a message.")
            .font(.callout.italic())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, density == .compact ? 7 : 9)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(I2Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
    }

    /// "edited": plain when there is no recoverable history, otherwise a
    /// toggle that reveals the prior versions iMessage-style.
    @ViewBuilder
    private var editedLabel: some View {
        if message.editHistory.isEmpty {
            Text("edited")
        } else {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isEditHistoryExpanded.toggle()
                }
            } label: {
                Text(isEditHistoryExpanded ? "hide edits" : "edited")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEditHistoryExpanded ? "Hide edit history" : "Show edit history")
        }
    }

    /// Prior versions of the message, dimmed and stacked above the current
    /// bubble, each with the time it was superseded.
    private var editHistoryList: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            ForEach(Array(message.editHistory.enumerated()), id: \.offset) { _, version in
                VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 1) {
                    Text(version.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(I2Palette.elevatedBackground.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(I2Palette.separator.opacity(0.6), lineWidth: 1)
                        }

                    Text(version.editedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Outgoing status with the actual receipt time when known
    /// ("read 3:42 PM" beats a bare "read").
    private var deliveryStatusText: String {
        switch message.status {
        case .read:
            if let readAt = message.readAt {
                return "read \(readAt.formatted(date: .omitted, time: .shortened))"
            }
            return "read"
        case .delivered:
            if let deliveredAt = message.deliveredAt {
                return "delivered \(deliveredAt.formatted(date: .omitted, time: .shortened))"
            }
            return "delivered"
        default:
            return message.status.statusLabel
        }
    }
}

/// Data-detector-style affordance shown under a message when it mentions a
/// date/time, offering to save it to the calendar.
private struct CalendarSuggestionChip: View {
    let mention: DetectedDateMention
    var add: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus")
                    .font(.caption2.weight(.semibold))
                Text("Add “\(mention.matchedText)” to Calendar")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(hovering ? 0.18 : 0.11), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add to your calendar (Google, if configured in macOS Calendar)")
        .accessibilityLabel("Add \(mention.matchedText) to calendar")
    }
}

/// Slack-style "N replies" affordance shown under a message that anchors a
/// thread. Tapping it opens the docked thread pane.
private struct ThreadIndicatorChip: View {
    let count: Int
    let repliers: [Contact?]
    let lastReplyAt: Date?
    var hasNewActivity: Bool = false
    var open: () -> Void
    @State private var hovering = false

    private var uniqueRepliers: [Contact?] {
        var seen = Set<String>()
        var result: [Contact?] = []
        for contact in repliers {
            let key = contact?.id.rawValue ?? "unknown"
            if seen.insert(key).inserted { result.append(contact) }
            if result.count == 3 { break }
        }
        return result
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                if hasNewActivity {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .transition(.scale.combined(with: .opacity))
                }

                HStack(spacing: -6) {
                    ForEach(Array(uniqueRepliers.enumerated()), id: \.offset) { _, contact in
                        AvatarView(contact: contact, size: 18)
                            .overlay(Circle().stroke(I2Palette.appBackground, lineWidth: 1.5))
                    }
                }

                Text(hasNewActivity ? "New reply" : (count == 1 ? "1 reply" : "\(count) replies"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                if let lastReplyAt {
                    Text(lastReplyAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0.45)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(hasNewActivity ? 0.18 : (hovering ? 0.16 : 0.09)), in: Capsule())
            .overlay(
                Capsule().stroke(Color.accentColor.opacity(hasNewActivity ? 0.5 : 0), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open thread")
        .accessibilityLabel("\(count) replies. Open thread.")
    }
}

private struct QuotedReplyView: View {
    let message: Message
    let senderName: String
    var jump: () -> Void

    var body: some View {
        Button(action: jump) {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor.opacity(0.8))

                Text(senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                    .lineLimit(1)

                Text(message.body.plainText.isEmpty ? "Attachment" : message.body.plainText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .help("Jump to replied message")
        .accessibilityLabel("In reply to \(senderName): \(message.body.plainText)")
    }
}

private struct ComposerView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var composerFocused: Bool
    @State private var isDropTargeted = false
    @State private var measuredTextHeight: CGFloat = 36

    let conversation: Conversation

    private var composerHeight: CGFloat {
        min(max(measuredTextHeight, 36), 120)
    }

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

                EmojiPickerControl(
                    accessibilityLabel: "Insert emoji in message composer",
                    helpText: "Insert emoji",
                    popoverTitle: "Message emoji",
                    customPlaceholder: "Paste emoji"
                ) { emoji in
                    model.insertEmojiInCurrentDraft(emoji)
                    composerFocused = true
                }

                ZStack(alignment: .topLeading) {
                    // Invisible mirror of the draft text so the composer grows
                    // with its content between the min and max heights below.
                    Text(model.currentDraftText.isEmpty ? " " : model.currentDraftText)
                        .font(.body)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            measuredTextHeight = height
                        }
                        .opacity(0)
                        .accessibilityHidden(true)

                    if model.currentDraftText.isEmpty {
                        Text("Message \(conversation.title)")
                            .font(.body)
                            .foregroundStyle(Color(nsColor: .placeholderTextColor))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
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
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 8)
                    .focused($composerFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.isEmpty else {
                            return .ignored
                        }
                        if model.canSendCurrentDraft {
                            Task { await model.sendCurrentDraft() }
                        }
                        return .handled
                    }
                    .accessibilityLabel("Message composer")
                }
                .frame(height: composerHeight)
                .padding(.horizontal, 4)
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
                .disabled(!model.canSendCurrentDraft)
                .help("Send (Return)")
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: I2Layout.composerMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(I2Palette.appBackground)
        .onChange(of: model.focusRequest) { _, request in
            guard request == .composer else { return }
            composerFocused = true
            model.consumeFocusRequest(.composer)
        }
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

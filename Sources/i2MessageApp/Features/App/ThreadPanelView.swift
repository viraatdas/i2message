import SwiftUI
import i2MessageCore

/// Slack-style thread pane docked to the right of the transcript. Shows the
/// thread's root message followed by every reply, all in one focused column.
struct ThreadPanelView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            I2Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(model.threadPanelMessages.enumerated()), id: \.element.id) { index, message in
                            ThreadMessageRow(
                                message: message,
                                senderName: model.senderName(for: message),
                                sender: model.contact(for: message.senderID),
                                isRoot: index == 0
                            )
                            .id(message.id)

                            if index == 0, model.threadPanelMessages.count > 1 {
                                replyDivider(count: model.threadPanelMessages.count - 1)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.threadPanelMessages.last?.id) { _, last in
                    if let last {
                        withAnimation(I2Motion.stateChange(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            I2Divider()
            composer
        }
        .frame(maxHeight: .infinity)
        .background(I2Palette.sidebarBackground)
        // Opening a thread (click or swipe) is an intent to reply — put the
        // caret straight into the composer.
        .onAppear { isComposerFocused = true }
        .onChange(of: model.threadRootID) { _, rootID in
            if rootID != nil {
                isComposerFocused = true
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            EmojiPickerControl(
                accessibilityLabel: "Insert emoji in thread reply composer",
                helpText: "Insert emoji in thread reply"
            ) {
                isComposerFocused = true
            }

            TextField(
                model.isUsingLiveData ? "Continue reply in Messages…" : "Reply in thread…",
                text: $model.threadDraftText,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .focused($isComposerFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(I2Palette.separator, lineWidth: 1)
                )
                .onSubmit {
                    if model.canSendThreadReply {
                        Task { await model.sendThreadReply() }
                    }
                }
                .accessibilityLabel("Thread reply composer")
                .accessibilityHint(model.isUsingLiveData ? "The draft will open in Messages for a real threaded reply" : "Type a reply for the open thread")

            Button {
                Task { await model.sendThreadReply() }
            } label: {
                Image(systemName: model.isUsingLiveData ? "arrow.up.forward.app.fill" : "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.iconOnly)
            .disabled(!model.canSendThreadReply)
            .help(model.isUsingLiveData ? "Continue threaded reply in Messages (Return)" : "Send reply in thread (Return)")
            .accessibilityLabel(model.isUsingLiveData ? "Continue reply in Messages" : "Send thread reply")
            .accessibilityHint(model.isUsingLiveData ? "Copies the draft and opens Messages for the threaded reply" : "Sends the draft in the thread panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("Thread")
                    .font(.headline)
                let count = model.threadPanelMessages.count - 1
                Text(count == 1 ? "1 reply" : "\(max(count, 0)) replies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                model.closeThread()
            } label: {
                Image(systemName: "xmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close thread (Esc)")
            .accessibilityLabel("Close thread")
            .accessibilityHint("Closes the thread panel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func replyDivider(count: Int) -> some View {
        HStack(spacing: 8) {
            Text(count == 1 ? "1 reply" : "\(count) replies")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Rectangle()
                .fill(I2Palette.separator)
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

private struct ThreadMessageRow: View {
    let message: Message
    let senderName: String
    let sender: Contact?
    let isRoot: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.direction == .outgoing {
                AvatarInitialsBubble()
            } else {
                AvatarView(contact: sender, size: 30)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(senderName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if isRoot {
                        Text("· original")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !message.body.plainText.isEmpty {
                    Text(message.body.plainText.linkifiedAttributedString)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(message.attachments) { attachment in
                    InlineAttachmentView(attachment: attachment, maxWidth: 260)
                }
            }
        }
        .padding(10)
        .background(
            isRoot ? I2Palette.incomingBubble.opacity(0.55) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

/// A tiny neutral avatar stand-in for the current user in the thread pane.
private struct AvatarInitialsBubble: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.22))
            .frame(width: 30, height: 30)
            .overlay {
                Text("You".prefix(1))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
    }
}

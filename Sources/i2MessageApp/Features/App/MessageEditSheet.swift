import SwiftUI

struct MessageEditSheet: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool

    var body: some View {
        if let draft = model.messageEditDraft {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    header(for: draft)
                    I2Divider()

                    VStack(alignment: .leading, spacing: 18) {
                        originalMessage(for: draft)
                        replacementEditor(for: draft, at: context.date)

                        if draft.editsLocally {
                            localEditNote
                        } else {
                            messagesHandoffGuide
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)

                    I2Divider()
                    footer(for: draft, at: context.date)
                }
                .frame(width: 600)
                .background(I2Palette.elevatedBackground)
                .interactiveDismissDisabled(model.isCompletingMessageEdit)
                .animation(I2Motion.stateChange(reduceMotion: reduceMotion), value: model.messageEditReadiness(at: context.date))
            }
            .onAppear { editorFocused = true }
        }
    }

    private func header(for draft: MessageEditDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.line")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(I2Palette.selectionFill, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Edit sent message")
                    .font(.title3.weight(.semibold))
                Text(draft.editsLocally ? "Update the sample transcript" : "Prepare a replacement, then finish in Messages")
                    .font(.caption)
                    .foregroundStyle(I2Palette.secondaryText)
            }

            Spacer(minLength: 16)

            if draft.editsLocally {
                I2Pill(title: "Sample", systemImage: "sparkles", tint: Color.accentColor)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func originalMessage(for draft: MessageEditDraft) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Original message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(I2Palette.secondaryText)

            Text(draft.originalText)
                .font(.callout)
                .foregroundStyle(I2Palette.primaryText)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(I2Palette.appBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(I2Palette.separator, lineWidth: I2Layout.hairlineWidth)
                }
                .accessibilityLabel("Original message: \(draft.originalText)")
        }
    }

    private func replacementEditor(for draft: MessageEditDraft, at date: Date) -> some View {
        let readiness = model.messageEditReadiness(at: date)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Replacement")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(I2Palette.secondaryText)

                Spacer()

                Text("\(draft.text.count) characters")
                    .font(.caption2)
                    .foregroundStyle(I2Palette.tertiaryText)
                    .monospacedDigit()
            }

            TextEditor(text: Binding(
                get: { model.messageEditDraft?.text ?? "" },
                set: { model.updateMessageEditText($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(9)
            .frame(minHeight: 118, maxHeight: 150)
            .background(I2Palette.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(editorBorder(for: readiness), lineWidth: editorFocused ? 2 : I2Layout.hairlineWidth)
            }
            .focused($editorFocused)
            .accessibilityLabel("Replacement message text")
            .accessibilityHint("Edit the sent message. Press Command-Return to continue.")

            validationRow(for: readiness)
        }
    }

    private func validationRow(for readiness: MessageEditReadiness) -> some View {
        HStack(spacing: 6) {
            Image(systemName: validationSymbol(for: readiness))
                .accessibilityHidden(true)
            Text(validationText(for: readiness))
                .lineLimit(2)
            Spacer(minLength: 12)
            if readiness == .ready {
                Text("⌘↩ to continue")
                    .foregroundStyle(I2Palette.tertiaryText)
            }
        }
        .font(.caption)
        .foregroundStyle(validationColor(for: readiness))
        .accessibilityElement(children: .combine)
    }

    private var localEditNote: some View {
        Label {
            Text("Saving keeps the previous text in this message's edit history.")
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Color.accentColor)
        }
        .font(.callout)
        .foregroundStyle(I2Palette.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(I2Palette.infoFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var messagesHandoffGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("Finish in Messages", systemImage: "arrow.up.forward.app")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(I2Palette.primaryText)

                Spacer()

                Text("Replacement copies automatically")
                    .font(.caption2)
                    .foregroundStyle(I2Palette.secondaryText)
            }

            HStack(spacing: 10) {
                handoffStep(number: 1, title: "Control-click", detail: "original bubble")
                handoffChevron
                handoffStep(number: 2, title: "Choose Edit", detail: "then paste")
                handoffChevron
                handoffStep(number: 3, title: "Press Return", detail: "to send update")
            }
        }
        .padding(12)
        .background(I2Palette.infoFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finish in Messages. Control-click the original bubble, choose Edit, paste the replacement, then press Return.")
    }

    private func handoffStep(number: Int, title: String, detail: String) -> some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(I2Palette.selectionFill, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(I2Palette.primaryText)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(I2Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var handoffChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(I2Palette.tertiaryText)
            .accessibilityHidden(true)
    }

    private func footer(for draft: MessageEditDraft, at date: Date) -> some View {
        HStack(spacing: 12) {
            availability(for: draft, at: date)

            Spacer(minLength: 16)

            Button("Cancel") {
                model.cancelMessageEdit()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(model.isCompletingMessageEdit)

            Button {
                Task { await model.completeMessageEdit() }
            } label: {
                if model.isCompletingMessageEdit {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text(draft.editsLocally ? "Saving…" : "Opening Messages…")
                    }
                } else {
                    Label(
                        draft.editsLocally ? "Save edit" : "Continue in Messages",
                        systemImage: draft.editsLocally ? "checkmark" : "arrow.up.forward.app"
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.canCompleteMessageEdit(at: date))
            .help(draft.editsLocally ? "Save edit (Command-Return)" : "Copy replacement and open Messages (Command-Return)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func availability(for draft: MessageEditDraft, at date: Date) -> some View {
        if let deadline = draft.editDeadline {
            HStack(spacing: 8) {
                Label(remainingTime(until: deadline, at: date), systemImage: "clock")
                Text("·")
                    .foregroundStyle(I2Palette.tertiaryText)
                Text("\(draft.editsRemaining) \(draft.editsRemaining == 1 ? "edit" : "edits") left")
            }
            .font(.caption)
            .foregroundStyle(deadline > date ? I2Palette.secondaryText : Color(nsColor: .systemOrange))
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        } else {
            Label("Edit history will be preserved", systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(I2Palette.secondaryText)
        }
    }

    private func remainingTime(until deadline: Date, at date: Date) -> String {
        let seconds = min(15 * 60, max(0, Int(deadline.timeIntervalSince(date).rounded(.up))))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d left", minutes, remainder)
    }

    private func editorBorder(for readiness: MessageEditReadiness) -> Color {
        if case .unavailable = readiness {
            return Color(nsColor: .systemOrange)
        }
        if readiness == .empty {
            return Color(nsColor: .systemRed)
        }
        return editorFocused ? Color.accentColor : I2Palette.separator
    }

    private func validationSymbol(for readiness: MessageEditReadiness) -> String {
        switch readiness {
        case .ready: "checkmark.circle.fill"
        case .empty: "exclamationmark.circle.fill"
        case .unavailable: "clock.badge.exclamationmark"
        case .unchanged: "info.circle"
        }
    }

    private func validationText(for readiness: MessageEditReadiness) -> String {
        switch readiness {
        case .ready: "Ready to continue"
        case .empty: "Replacement text can't be empty"
        case let .unavailable(message): message
        case .unchanged: "Make a change to continue"
        }
    }

    private func validationColor(for readiness: MessageEditReadiness) -> Color {
        switch readiness {
        case .ready: Color(nsColor: .systemGreen)
        case .empty: Color(nsColor: .systemRed)
        case .unavailable: Color(nsColor: .systemOrange)
        case .unchanged: I2Palette.secondaryText
        }
    }
}

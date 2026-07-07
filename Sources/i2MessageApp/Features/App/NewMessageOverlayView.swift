import SwiftUI
import i2MessageCore

/// Floating Cmd+N recipient picker. Starts a new conversation inside the same
/// window instead of handing off to Messages.app.
struct NewMessageOverlayView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var recipientFocused: Bool
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { model.closeNewMessage() }

            VStack(spacing: 0) {
                recipientField
                if !model.newMessageSuggestions.isEmpty {
                    I2Divider()
                    suggestionList
                }
            }
            .frame(width: 560)
            .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 26, y: 18)
            .padding(.top, 84)
        }
        .onAppear { recipientFocused = true }
        .onExitCommand { model.closeNewMessage() }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .newMessageRecipient else { return }
            recipientFocused = true
            model.consumeFocusRequest(.newMessageRecipient)
        }
        .onChange(of: model.newMessageQuery) { _, text in
            scheduleSuggestions(text)
        }
        .accessibilityElement(children: .contain)
    }

    private var recipientField: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.secondary)

            TextField("To: name, phone, or email", text: $model.newMessageQuery)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($recipientFocused)
                .onSubmit(handleSubmit)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.newMessageSuggestions) { contact in
                    Button {
                        Task { await model.startConversation(with: contact) }
                    } label: {
                        HStack(spacing: 10) {
                            AvatarView(contact: contact, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.displayName)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                if let handle = contact.handles.first {
                                    Text(handle.value)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowHighlightButtonStyle())
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 300)
    }

    private func handleSubmit() {
        if let first = model.newMessageSuggestions.first {
            Task { await model.startConversation(with: first) }
        } else {
            let query = model.newMessageQuery
            Task { await model.startConversation(withHandle: query) }
        }
    }

    private func scheduleSuggestions(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await model.updateNewMessageQuery(text)
        }
    }
}

/// Subtle hover/press highlight shared by overlay rows.
struct RowHighlightButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed || hovering ? I2Palette.selectionFill : Color.clear)
                    .padding(.horizontal, 6)
            )
            .onHover { hovering = $0 }
    }
}

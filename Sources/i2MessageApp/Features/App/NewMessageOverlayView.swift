import SwiftUI
import i2MessageCore

/// Floating Cmd+N recipient picker. Starts a new conversation inside the same
/// window instead of handing off to Messages.app.
struct NewMessageOverlayView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var recipientFocused: Bool
    @State private var debounceTask: Task<Void, Never>?
    /// Index of the keyboard-highlighted suggestion. Kept in range as the
    /// suggestion list changes; Return starts a chat with this row.
    @State private var selectedIndex = 0

    var body: some View {
        ZStack {
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
            .offset(y: -40)
        }
        .onAppear { recipientFocused = true }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
        }
        .onExitCommand { model.closeNewMessage() }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .newMessageRecipient else { return }
            recipientFocused = true
            model.consumeFocusRequest(.newMessageRecipient)
        }
        .onChange(of: model.newMessageQuery) { _, text in
            // Reset the highlight to the top when the query itself changes, but
            // not when the same query's results merely refresh (e.g. background
            // indexing) — otherwise arrow-key navigation keeps snapping back.
            selectedIndex = 0
            scheduleSuggestions(text)
        }
        .onChange(of: model.newMessageSuggestions.count) { _, count in
            // Keep the highlight in range if the list shrinks.
            if selectedIndex >= count { selectedIndex = max(0, count - 1) }
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
                .onKeyPress(.downArrow) { moveSelection(1) }
                .onKeyPress(.upArrow) { moveSelection(-1) }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private var suggestionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.newMessageSuggestions.enumerated()), id: \.element.id) { index, contact in
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
                        .buttonStyle(RowHighlightButtonStyle(isSelected: index == selectedIndex))
                        .id(index)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
            .onChange(of: selectedIndex) { _, index in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    @discardableResult
    private func moveSelection(_ delta: Int) -> KeyPress.Result {
        let count = model.newMessageSuggestions.count
        guard count > 0 else { return .ignored }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
        return .handled
    }

    private func handleSubmit() {
        debounceTask?.cancel()
        debounceTask = nil
        let suggestions = model.newMessageSuggestions
        let selectedID = suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex].id : nil
        Task { await model.submitNewMessage(selectedSuggestionID: selectedID) }
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

/// Subtle hover/press highlight shared by overlay rows. `isSelected` lets
/// keyboard navigation light up a row the same way hovering does.
struct RowHighlightButtonStyle: ButtonStyle {
    var isSelected = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed || hovering || isSelected ? I2Palette.selectionFill : Color.clear)
                    .padding(.horizontal, 6)
            )
            .onHover { hovering = $0 }
    }
}

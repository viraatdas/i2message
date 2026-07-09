import AppKit
import SwiftUI

enum EmojiCatalog {
    static let common: [String] = [
        "😀", "😂", "🥰", "😎", "😭", "😅", "🙏", "👏",
        "👍", "👎", "🙌", "🤝", "💪", "🫡", "🎉", "✨",
        "❤️", "💙", "🔥", "✅", "❌", "⭐️", "💡", "📌",
        "👀", "🤔", "😮", "😢", "😡", "🤯", "👌", "🚀",
    ]

    static func normalizedEmoji(from rawValue: String) -> String? {
        for character in rawValue.trimmingCharacters(in: .whitespacesAndNewlines) where character.isEmojiCandidate {
            return String(character)
        }
        return nil
    }
}

/// The composer emoji button. Clicking it focuses the composer and opens
/// macOS's own Emoji & Symbols picker (the same one as ⌃⌘Space), which inserts
/// straight into the focused field — no intermediate popover to click through.
struct EmojiPickerControl: View {
    let accessibilityLabel: String
    let helpText: String
    /// Focuses the composer this control feeds. The native picker inserts into
    /// the first responder, so the composer must be focused first for the emoji
    /// to land in the draft.
    var focusComposer: () -> Void

    var body: some View {
        Button {
            focusComposer()
            NSApplication.shared.orderFrontCharacterPalette(nil)
        } label: {
            Label("Emoji", systemImage: "face.smiling")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct EmojiPickerPopover: View {
    let title: String
    let customPlaceholder: String
    var insert: (String) -> Void

    @State private var customEmoji = ""
    @FocusState private var customFieldFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 5), count: 8)

    private var normalizedCustomEmoji: String? {
        EmojiCatalog.normalizedEmoji(from: customEmoji)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    NSApplication.shared.orderFrontCharacterPalette(nil)
                    customFieldFocused = true
                } label: {
                    Label("Character Viewer", systemImage: "keyboard")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Open macOS Character Viewer")
                .accessibilityLabel("Open Character Viewer")
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                ForEach(EmojiCatalog.common, id: \.self) { emoji in
                    Button {
                        insert(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 16))
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Insert \(emoji)")
                    .accessibilityLabel("Insert \(emoji)")
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField(customPlaceholder, text: $customEmoji)
                    .textFieldStyle(.roundedBorder)
                    .focused($customFieldFocused)
                    .onSubmit(insertCustomEmoji)
                    .accessibilityLabel(customPlaceholder)

                Button("Insert") {
                    insertCustomEmoji()
                }
                .disabled(normalizedCustomEmoji == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(12)
        .onAppear {
            customFieldFocused = true
        }
    }

    private func insertCustomEmoji() {
        guard let emoji = normalizedCustomEmoji else {
            return
        }
        insert(emoji)
        customEmoji = ""
    }
}

private extension Character {
    var isEmojiCandidate: Bool {
        let scalars = unicodeScalars
        guard scalars.contains(where: { $0.properties.isEmoji }) else {
            return false
        }
        if scalars.contains(where: { $0.properties.isEmojiPresentation }) {
            return true
        }
        if scalars.contains(where: { $0.value == 0xFE0F || $0.value == 0x20E3 || $0.value == 0x200D }) {
            return true
        }
        return scalars.contains { scalar in
            scalar.properties.generalCategory == .otherSymbol
                || scalar.properties.generalCategory == .modifierSymbol
        }
    }
}

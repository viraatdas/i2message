import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var paletteFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    model.closeCommandPalette()
                }

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "command")
                        .foregroundStyle(.secondary)
                    TextField("Run command", text: $model.commandPaletteQuery)
                        .textFieldStyle(.plain)
                        .focused($paletteFocused)
                        .onSubmit {
                            if let command = model.availableCommands.first {
                                Task { await model.perform(command) }
                            }
                        }
                    Button {
                        model.closeCommandPalette()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Close")
                }
                .padding(14)

                I2Divider()

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.availableCommands) { command in
                            Button {
                                Task { await model.perform(command) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: command.symbolName)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(command.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(command.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if let shortcutText = command.shortcutText {
                                        Text(shortcutText)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 560)
            .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 24, y: 16)
        }
        .onAppear {
            paletteFocused = true
        }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .commandPalette else { return }
            paletteFocused = true
            model.consumeFocusRequest(.commandPalette)
        }
        .accessibilityElement(children: .contain)
    }
}

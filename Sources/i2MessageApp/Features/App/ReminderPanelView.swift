import SwiftUI

/// Floating Cmd+I panel: pick when to be reminded about the selected chat.
struct ReminderPanelView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var customMinutes = ""
    @FocusState private var customFocused: Bool

    private static let presets: [(label: String, spoken: String, interval: TimeInterval)] = [
        ("In 20 minutes", "in 20 minutes", 20 * 60),
        ("In 1 hour", "in 1 hour", 60 * 60),
        ("In 3 hours", "in 3 hours", 3 * 60 * 60),
        ("Tomorrow morning", "tomorrow morning", 0),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    model.closeReminderPanel()
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(Color.accentColor)
                    Text("Remind me about \(model.selectedConversation?.title ?? "this chat")")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(14)

                I2Divider()

                VStack(spacing: 4) {
                    ForEach(Self.presets, id: \.label) { preset in
                        Button {
                            Task {
                                await model.scheduleReminder(
                                    after: preset.interval == 0 ? Self.untilTomorrowMorning() : preset.interval,
                                    label: preset.spoken
                                )
                            }
                        } label: {
                            HStack {
                                Text(preset.label)
                                    .font(.callout)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        TextField("Custom minutes", text: $customMinutes)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .focused($customFocused)
                            .onSubmit(scheduleCustom)
                        Button("Set", action: scheduleCustom)
                            .disabled(Int(customMinutes) == nil)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .padding(.vertical, 6)
            }
            .frame(width: 380)
            .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 26, y: 18)
        }
        .onExitCommand {
            model.closeReminderPanel()
        }
        .accessibilityElement(children: .contain)
    }

    private func scheduleCustom() {
        guard let minutes = Int(customMinutes), minutes > 0 else {
            return
        }
        Task {
            await model.scheduleReminder(after: TimeInterval(minutes * 60), label: "in \(minutes) minutes")
        }
    }

    private static func untilTomorrowMorning() -> TimeInterval {
        let calendar = Calendar.current
        let tomorrow9 = calendar.date(
            bySettingHour: 9, minute: 0, second: 0,
            of: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        ) ?? Date().addingTimeInterval(16 * 60 * 60)
        return max(60, tomorrow9.timeIntervalSinceNow)
    }
}

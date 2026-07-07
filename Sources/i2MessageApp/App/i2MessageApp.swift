import SwiftUI

@main
struct i2MessageApp: App {
    @StateObject private var model = AppViewModel(dependencies: .live())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    Task { await model.perform(.newMessage) }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandGroup(after: .appSettings) {
                Button("i2Message Settings") {
                    model.isSettingsPresented = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Conversation") {
                Button("Next Conversation") {
                    Task { await model.perform(.nextConversation) }
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])

                Button("Previous Conversation") {
                    Task { await model.perform(.previousConversation) }
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])

                Divider()

                Button("Search This Chat") {
                    Task { await model.perform(.searchCurrentChat) }
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Search All Chats") {
                    Task { await model.perform(.openSearch) }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Toggle Sidebar") {
                    model.cycleSidebarMode()
                }
                .keyboardShortcut("s", modifiers: [.command])

                Divider()

                Button("Mark Unread and Next") {
                    Task { await model.markSelectedUnreadAndAdvance() }
                }
                .keyboardShortcut("u", modifiers: [.command])

                Button("Chat Info") {
                    Task { await model.openInfoPanel() }
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Remind Me…") {
                    model.openReminderPanel()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(model.searchMode == .semantic ? "Use Exact Search" : "Use Semantic Search") {
                    Task { await model.perform(.toggleSemantic) }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Command Palette") {
                    model.openCommandPalette()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

            CommandMenu("Diagnostics") {
                Button("Rebuild Local Indexes") {
                    Task { await model.perform(.rebuildIndexes) }
                }

                Button(model.isOffline ? "Disable Offline Mode" : "Preview Offline Mode") {
                    Task { await model.perform(.toggleOffline) }
                }

                Button("Show Error Banner") {
                    Task { await model.perform(.simulateError) }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 660, minHeight: 540)
        }
    }
}

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

                Button("Focus Filter") {
                    Task { await model.perform(.focusFilter) }
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Open Search") {
                    Task { await model.perform(.openSearch) }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button(model.searchMode == .semantic ? "Use Exact Search" : "Use Semantic Search") {
                    Task { await model.perform(.toggleSemantic) }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Command Palette") {
                    model.openCommandPalette()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
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

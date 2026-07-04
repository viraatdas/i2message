import SwiftUI

@main
struct i2MessageApp: App {
    @StateObject private var model = MockInboxViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Conversation") {
                Button("Next Conversation") {
                    model.selectNextConversation()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])

                Button("Previous Conversation") {
                    model.selectPreviousConversation()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])

                Divider()

                Button(model.semanticSearchEnabled ? "Use Exact Search" : "Use Semantic Search") {
                    model.semanticSearchEnabled.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}

import AppKit
import SwiftUI
import i2MessageCore

struct ContentView: View {
    @EnvironmentObject private var model: MockInboxViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            ConversationDetailView()
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search messages")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.semanticSearchEnabled.toggle()
                } label: {
                    Label(model.semanticSearchEnabled ? "Semantic search on" : "Exact search", systemImage: model.semanticSearchEnabled ? "sparkles" : "magnifyingglass")
                }
                .help(model.semanticSearchEnabled ? "Semantic search on" : "Exact search")
                .accessibilityLabel(model.semanticSearchEnabled ? "Semantic search on" : "Exact search")

                Button {
                    model.openNewConversationHandoff()
                } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }
                .help("Open Messages.app for a new conversation")
                .accessibilityLabel("New message handoff")
            }
        }
        .onAppear {
            model.refreshIntegrationStatus()
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.selectedConversationID)
    }
}

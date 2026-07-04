import SwiftUI
import i2MessageCore

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: I2Layout.sidebarMinWidth,
                    ideal: I2Layout.sidebarIdealWidth,
                    max: I2Layout.sidebarMaxWidth
                )
        } detail: {
            DetailRouterView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.perform(.openSearch) }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help("Open search workspace")

                Button {
                    model.openCommandPalette()
                } label: {
                    Label("Command Palette", systemImage: "command")
                }
                .help("Command palette")

                Button {
                    Task { await model.perform(.newMessage) }
                } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }
                .help("New message")
            }
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 660, minHeight: 540)
        }
        .overlay {
            if model.isCommandPalettePresented {
                CommandPaletteView()
                    .environmentObject(model)
                    .transition(.opacity)
            }
        }
        .task {
            await model.load()
        }
        .preferredColorScheme(model.settings.theme.colorScheme)
        .frame(minWidth: I2Layout.minWindowWidth, minHeight: I2Layout.minWindowHeight)
        .background(I2Palette.appBackground)
        .animation(I2Motion.stateChange(reduceMotion: reduceMotion), value: model.selectedConversationID)
        .animation(I2Motion.stateChange(reduceMotion: reduceMotion), value: model.sidebarDestination)
    }
}

private struct DetailRouterView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch model.sidebarDestination {
                case .conversations:
                    ConversationDetailView()
                case .contacts:
                    ContactsWorkspaceView()
                case .search:
                    SearchWorkspaceView()
                }
            }

            if let banner = model.statusBanner {
                StatusBannerView(
                    banner: banner,
                    action: {
                        if banner.actionTitle != nil {
                            model.isSettingsPresented = true
                        }
                    },
                    dismiss: model.dismissBanner
                )
            }
        }
        .background(I2Palette.appBackground)
    }
}

private extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

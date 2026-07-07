import SwiftUI
import i2MessageCore

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var contentFocused: Bool

    private var anyOverlayPresented: Bool {
        model.isCommandPalettePresented
            || model.isSearchOverlayPresented
            || model.isNewMessagePresented
            || model.isInfoPanelPresented
            || model.isReminderPresented
    }

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarMode != .hidden {
                SidebarView()
                    .frame(width: model.sidebarMode == .compact ? I2Layout.compactSidebarWidth : I2Layout.sidebarIdealWidth)
                    .transition(.move(edge: .leading))

                I2VerticalDivider()
            }

            DetailRouterView()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($contentFocused)
        .onKeyPress(.upArrow) {
            guard !anyOverlayPresented else { return .ignored }
            Task { await model.selectAdjacentConversation(offset: -1) }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !anyOverlayPresented else { return .ignored }
            Task { await model.selectAdjacentConversation(offset: 1) }
            return .handled
        }
        .animation(I2Motion.stateChange(reduceMotion: reduceMotion), value: model.sidebarMode)
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
            } else if model.isSearchOverlayPresented {
                SearchOverlayView()
                    .environmentObject(model)
                    .transition(.opacity)
            } else if model.isNewMessagePresented {
                NewMessageOverlayView()
                    .environmentObject(model)
                    .transition(.opacity)
            } else if model.isInfoPanelPresented {
                InfoPanelView()
                    .environmentObject(model)
                    .transition(.opacity)
            } else if model.isReminderPresented {
                ReminderPanelView()
                    .environmentObject(model)
                    .transition(.opacity)
            }
        }
        .task {
            await model.load()
            contentFocused = true
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
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
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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
        }
        .background(I2Palette.appBackground)
        .animation(I2Motion.stateChange(reduceMotion: reduceMotion), value: model.statusBanner)
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

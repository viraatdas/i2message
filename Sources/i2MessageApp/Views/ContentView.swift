import SwiftUI
import i2MessageCore

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var contentFocused: Bool
    @AppStorage("hasSeenShortcutTour") private var hasSeenShortcutTour = false

    private var anyOverlayPresented: Bool {
        model.isCommandPalettePresented
            || model.isSearchOverlayPresented
            || model.isNewMessagePresented
            || model.isInfoPanelPresented
            || model.isReminderPresented
    }

    private var sidebarWidth: CGFloat {
        switch model.sidebarMode {
        case .hidden: return 0
        case .compact: return I2Layout.compactSidebarWidth
        case .full: return I2Layout.sidebarIdealWidth
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Keep the sidebar mounted and animate its width straight to 0 when
            // hidden so all three states share one continuous glide instead of a
            // width tween fighting a slide-in/out transition.
            SidebarView()
                .frame(width: sidebarWidth, alignment: .leading)
                .clipped()
                .opacity(model.sidebarMode == .hidden ? 0 : 1)

            if model.sidebarMode != .hidden {
                I2VerticalDivider()
                    .transition(.opacity)
            }

            DetailRouterView()

            if model.isThreadPanelPresented {
                I2VerticalDivider()
                ThreadPanelView()
                    .frame(width: I2Layout.threadPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
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
        .onKeyPress(.escape) {
            model.dismissTopmostOverlay() ? .handled : .ignored
        }
        // Text fields swallow the raw Esc key and forward it as
        // cancelOperation instead — catch that path too so Esc closes
        // overlays even while typing in them.
        .onExitCommand {
            model.dismissTopmostOverlay()
        }
        .animation(I2Motion.sidebar(reduceMotion: reduceMotion), value: model.sidebarMode)
        .animation(I2Motion.overlay(reduceMotion: reduceMotion), value: model.isThreadPanelPresented)
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 660, minHeight: 540)
        }
        .overlay {
            Group {
                if model.isCommandPalettePresented {
                    CommandPaletteView()
                        .environmentObject(model)
                        .transition(I2Motion.overlayTransition)
                } else if model.isSearchOverlayPresented {
                    SearchOverlayView()
                        .environmentObject(model)
                        .transition(I2Motion.overlayTransition)
                } else if model.isNewMessagePresented {
                    NewMessageOverlayView()
                        .environmentObject(model)
                        .transition(I2Motion.overlayTransition)
                } else if model.isInfoPanelPresented {
                    InfoPanelView()
                        .environmentObject(model)
                        .transition(I2Motion.overlayTransition)
                } else if model.isReminderPresented {
                    ReminderPanelView()
                        .environmentObject(model)
                        .transition(I2Motion.overlayTransition)
                }
            }
            .animation(I2Motion.overlay(reduceMotion: reduceMotion), value: anyOverlayPresented)
        }
        .overlay {
            if model.isOnboardingPresented {
                OnboardingView {
                    hasSeenShortcutTour = true
                    model.isOnboardingPresented = false
                    contentFocused = true
                }
                .environmentObject(model)
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(I2Motion.overlay(reduceMotion: reduceMotion), value: model.isOnboardingPresented)
        .task {
            if !hasSeenShortcutTour {
                model.isOnboardingPresented = true
            }
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

import AppKit
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
            || model.messageEditDraft != nil
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

            ThreadPanelDock()
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
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 660, minHeight: 540)
        }
        .sheet(item: $model.messageEditDraft) { _ in
            MessageEditSheet()
                .environmentObject(model)
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
        // Re-check permissions whenever the app regains focus so a grant made
        // in System Settings (Full Disk Access, Contacts) is reflected on
        // return — in the onboarding setup page, the sidebar, and the banner.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.handleApplicationDidBecomeActive() }
        }
        .preferredColorScheme(model.settings.theme.colorScheme)
        .frame(minWidth: I2Layout.minWindowWidth, minHeight: I2Layout.minWindowHeight)
        .background(I2Palette.appBackground)
        .animation(I2Motion.stateChange(reduceMotion: reduceMotion), value: model.selectedConversationID)
        .animation(I2Motion.stateChange(reduceMotion: reduceMotion), value: model.sidebarDestination)
    }
}

private struct MessageEditSheet: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        if let draft = model.messageEditDraft {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.line")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit Message Text")
                            .font(.title3.weight(.semibold))
                        Text(draft.editsLocally ? "Sample transcript" : "Finish securely in Messages.app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(instructions(for: draft))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: Binding(
                    get: { model.messageEditDraft?.text ?? "" },
                    set: { model.updateMessageEditText($0) }
                ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(I2Palette.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(I2Palette.separator, lineWidth: 1)
                }
                .focused($editorFocused)
                .accessibilityLabel("Edited message text")

                HStack {
                    if !draft.editsLocally {
                        Label("iMessage allows up to 5 edits within 15 minutes", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Cancel") {
                        model.cancelMessageEdit()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isCompletingMessageEdit)

                    Button {
                        Task { await model.completeMessageEdit() }
                    } label: {
                        if model.isCompletingMessageEdit {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                draft.editsLocally ? "Save Edit" : "Copy & Open Messages",
                                systemImage: draft.editsLocally ? "checkmark" : "arrow.up.forward.app"
                            )
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCompleteMessageEdit)
                }
            }
            .padding(22)
            .frame(width: 540, height: 360)
            .interactiveDismissDisabled(model.isCompletingMessageEdit)
            .onAppear { editorFocused = true }
        }
    }

    private func instructions(for draft: MessageEditDraft) -> String {
        if draft.editsLocally {
            return "Change the text below. Saving keeps the previous version in the message's edit history."
        }
        return "macOS doesn't expose a supported edit command to other apps. Your replacement will be copied and Messages will open; Control-click the original bubble, choose Edit, paste, then press Return."
    }
}

private struct ThreadPanelDock: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            if model.isThreadPanelPresented {
                HStack(spacing: 0) {
                    I2VerticalDivider()

                    ThreadPanelView()
                        .frame(width: I2Layout.threadPanelWidth)
                }
                .frame(width: I2Layout.threadPanelDockWidth, alignment: .trailing)
                .transition(.opacity)
            }
        }
        .frame(
            width: model.isThreadPanelPresented ? I2Layout.threadPanelDockWidth : 0,
            alignment: .trailing
        )
        .frame(maxHeight: .infinity)
        .clipped()
        .animation(I2Motion.threadPanel(reduceMotion: reduceMotion), value: model.isThreadPanelPresented)
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

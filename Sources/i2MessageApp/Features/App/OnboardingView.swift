import SwiftUI
import i2MessageCore

/// First-launch shortcut tour: full-window overlay with one page per skill,
/// each demonstrated by a small looping animation. Re-openable any time with
/// ⌘/ or Help ▸ Shortcut Tour.
struct OnboardingView: View {
    var finish: () -> Void

    @State private var pageIndex = 0
    @FocusState private var isFocused: Bool

    private let pages = OnboardingPage.allPages

    var body: some View {
        ZStack {
            backgroundWash

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                pageContent
                    .frame(maxWidth: 560)
                    .id(pageIndex)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )

                Spacer(minLength: 16)

                footer
            }
            .padding(28)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) { retreat(); return .handled }
        .onKeyPress(.escape) { finish(); return .handled }
        .onKeyPress(.return) {
            if pageIndex == pages.count - 1 { finish() } else { advance() }
            return .handled
        }
        .accessibilityAddTraits(.isModal)
    }

    private var backgroundWash: some View {
        ZStack {
            I2Palette.appBackground
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear,
                    Color.accentColor.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var pageContent: some View {
        let page = pages[pageIndex]
        return VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(18)
                    .background(Color.accentColor.opacity(0.10), in: Circle())

                Text(page.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))

                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            page.demo
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .background(I2Palette.elevatedBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(I2Palette.separator, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(page.shortcuts) { row in
                    HStack(spacing: 10) {
                        KeyCapCluster(keys: row.keys)
                            .frame(width: 150, alignment: .trailing)
                        Text(row.action)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 26)
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") { finish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == pageIndex ? Color.accentColor : I2Palette.separator)
                        .frame(width: 7, height: 7)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                pageIndex = index
                            }
                        }
                }
            }

            Spacer()

            Button(pageIndex == pages.count - 1 ? "Start Messaging" : "Next") {
                if pageIndex == pages.count - 1 { finish() } else { advance() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 560)
    }

    private func advance() {
        guard pageIndex < pages.count - 1 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { pageIndex += 1 }
    }

    private func retreat() {
        guard pageIndex > 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { pageIndex -= 1 }
    }
}

// MARK: - Page model

private struct ShortcutRow: Identifiable {
    var id: String { keys.joined() + action }
    let keys: [String]
    let action: String
}

private struct OnboardingPage {
    let title: String
    let subtitle: String
    let systemImage: String
    let shortcuts: [ShortcutRow]
    let demo: AnyView

    @MainActor
    static let allPages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to i2Message",
            subtitle: "A fast, keyboard-first home for your Messages.",
            systemImage: "message.fill",
            shortcuts: [
                ShortcutRow(keys: ["⌘", "N"], action: "New message"),
                ShortcutRow(keys: ["⌘", "↩"], action: "Send"),
                ShortcutRow(keys: ["⌘", "/"], action: "Reopen this tour any time"),
            ],
            demo: AnyView(WelcomeDemo())
        ),
        OnboardingPage(
            title: "Fly Between Chats",
            subtitle: "Never touch the mouse to change conversations.",
            systemImage: "arrow.up.arrow.down",
            shortcuts: [
                ShortcutRow(keys: ["⌃", "⇥"], action: "Cycle chats (⇧ reverses)"),
                ShortcutRow(keys: ["⌘", "1–9", "0"], action: "Jump straight to a chat"),
                ShortcutRow(keys: ["↑", "↓"], action: "Step through the list"),
            ],
            demo: AnyView(ChatHopDemo())
        ),
        OnboardingPage(
            title: "Threads, Slack-Style",
            subtitle: "Swipe any bubble to reply in its own thread.",
            systemImage: "bubble.left.and.text.bubble.right",
            shortcuts: [
                ShortcutRow(keys: ["⇠ swipe"], action: "Open or start a thread"),
                ShortcutRow(keys: ["⌘", "↩"], action: "Send the thread reply"),
                ShortcutRow(keys: ["esc"], action: "Close the thread panel"),
            ],
            demo: AnyView(ThreadSwipeDemo())
        ),
        OnboardingPage(
            title: "Find Anything",
            subtitle: "Exact or semantic — your whole history, locally.",
            systemImage: "magnifyingglass",
            shortcuts: [
                ShortcutRow(keys: ["⌘", "F"], action: "Search this chat"),
                ShortcutRow(keys: ["⌘", "⇧", "P"], action: "Search every chat"),
                ShortcutRow(keys: ["⌘", "⇧", "K"], action: "Flip exact ↔ semantic"),
                ShortcutRow(keys: ["⌘", "K"], action: "Command palette"),
            ],
            demo: AnyView(SearchDemo())
        ),
        OnboardingPage(
            title: "Power Moves",
            subtitle: "The rest of the toolbelt, one key away.",
            systemImage: "bolt.fill",
            shortcuts: [
                ShortcutRow(keys: ["⌘", "S"], action: "Collapse or expand the sidebar"),
                ShortcutRow(keys: ["⌘", "U"], action: "Keep unread, hop to next"),
                ShortcutRow(keys: ["⌘", "I"], action: "Chat info & attachments"),
                ShortcutRow(keys: ["⌘", "R"], action: "Remind me about this chat"),
            ],
            demo: AnyView(SidebarToggleDemo())
        ),
    ]
}

// MARK: - Key caps

private struct KeyCapCluster: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, key.count > 1 ? 8 : 0)
                    .frame(minWidth: 26, minHeight: 26)
                    .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(I2Palette.separator, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
            }
        }
    }
}

private struct PulsingKeyCap: View {
    let label: String
    let pulse: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(pulse ? Color.accentColor : I2Palette.separator, lineWidth: pulse ? 1.5 : 1)
            }
            .scaleEffect(pulse ? 1.08 : 1)
            .shadow(color: pulse ? Color.accentColor.opacity(0.35) : .black.opacity(0.10), radius: pulse ? 5 : 1, y: 1)
    }
}

// MARK: - Demo: welcome bubbles

private struct WelcomeDemo: View {
    @State private var visibleCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            demoBubble("hey! 👋", incoming: true, visible: visibleCount >= 1)
            demoBubble("this is i2Message", incoming: true, visible: visibleCount >= 2)
            HStack {
                Spacer()
                demoBubble("let's go", incoming: false, visible: visibleCount >= 3)
            }
        }
        .padding(26)
        .task { await loop() }
    }

    private func demoBubble(_ text: String, incoming: Bool, visible: Bool) -> some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                incoming ? AnyShapeStyle(I2Palette.incomingBubble) : AnyShapeStyle(Color.accentColor.opacity(0.18)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .scaleEffect(visible ? 1 : 0.6, anchor: incoming ? .bottomLeading : .bottomTrailing)
            .opacity(visible ? 1 : 0)

    }

    private func loop() async {
        while !Task.isCancelled {
            for step in 1...3 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { visibleCount = step }
                try? await Task.sleep(nanoseconds: 550_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeOut(duration: 0.25)) { visibleCount = 0 }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

// MARK: - Demo: hopping between chats

private struct ChatHopDemo: View {
    @State private var selectedRow = 0
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(I2Palette.separator)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(I2Palette.separator).frame(width: 72, height: 6)
                            Capsule().fill(I2Palette.separator.opacity(0.6)).frame(width: 104, height: 5)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        selectedRow == row ? Color.accentColor.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
            }
            .frame(width: 190)

            PulsingKeyCap(label: "⌃ ⇥", pulse: pulse)
        }
        .padding(20)
        .task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeIn(duration: 0.12)) { pulse = true }
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                selectedRow = (selectedRow + 1) % 4
                pulse = false
            }
        }
    }
}

// MARK: - Demo: swipe to thread

private struct ThreadSwipeDemo: View {
    @State private var bubbleOffset: CGFloat = 0
    @State private var arrowVisible = false
    @State private var panelVisible = false
    @State private var replyVisible = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .opacity(arrowVisible ? 1 : 0)
                    Text("lunch tomorrow?")
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(I2Palette.incomingBubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .offset(x: bubbleOffset)
                }
                Text("swipe →")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Mini thread panel.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Thread")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                }
                Capsule().fill(I2Palette.separator).frame(width: 90, height: 6)
                Text("yes! 12:30?")
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .opacity(replyVisible ? 1 : 0)
                    .scaleEffect(replyVisible ? 1 : 0.7, anchor: .bottomLeading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 150, height: 120)
            .background(I2Palette.sidebarBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }
            .offset(x: panelVisible ? 0 : 170)
            .opacity(panelVisible ? 1 : 0)
        }
        .padding(22)
        .clipped()
        .task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                bubbleOffset = 30
                arrowVisible = true
            }
            try? await Task.sleep(nanoseconds: 550_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                bubbleOffset = 0
                panelVisible = true
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { replyVisible = true }
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                arrowVisible = false
                panelVisible = false
                replyVisible = false
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

// MARK: - Demo: search

private struct SearchDemo: View {
    private static let query = "dinner friday"
    @State private var typedCount = 0
    @State private var resultsVisible = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(String(Self.query.prefix(typedCount)))
                    .font(.callout)
                + Text("▏")
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }
            .frame(width: 280)

            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 8) {
                        Circle().fill(I2Palette.separator).frame(width: 14, height: 14)
                        Capsule().fill(I2Palette.separator).frame(width: row == 0 ? 150 : 118, height: 6)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(row == 0 ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(resultsVisible > row ? 1 : 0)
                    .offset(y: resultsVisible > row ? 0 : 6)
                }
            }
            .frame(width: 280)
        }
        .padding(20)
        .task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled {
            for count in 1...Self.query.count {
                typedCount = count
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
            for row in 1...2 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { resultsVisible = row }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                typedCount = 0
                resultsVisible = 0
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }
}

// MARK: - Demo: sidebar toggle

private struct SidebarToggleDemo: View {
    @State private var sidebarVisible = true
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 0) {
                // Sidebar pane.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 6) {
                            Circle().fill(I2Palette.separator).frame(width: 12, height: 12)
                            Capsule().fill(I2Palette.separator).frame(width: 56, height: 5)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(9)
                .frame(width: sidebarVisible ? 104 : 0, alignment: .leading)
                .background(I2Palette.sidebarBackground)
                .clipped()

                if sidebarVisible {
                    Rectangle().fill(I2Palette.separator).frame(width: 1)
                }

                // Transcript pane.
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(I2Palette.incomingBubble).frame(width: 92, height: 13)
                    Capsule().fill(I2Palette.incomingBubble).frame(width: 66, height: 13)
                    HStack {
                        Spacer()
                        Capsule().fill(Color.accentColor.opacity(0.2)).frame(width: 80, height: 13)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 250, height: 116)
            .background(I2Palette.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }

            PulsingKeyCap(label: "⌘ S", pulse: pulse)
        }
        .padding(20)
        .task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeIn(duration: 0.12)) { pulse = true }
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                sidebarVisible.toggle()
                pulse = false
            }
        }
    }
}

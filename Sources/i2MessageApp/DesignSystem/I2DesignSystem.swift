import AppKit
import SwiftUI

enum I2Layout {
    static let minWindowWidth: CGFloat = 920
    static let minWindowHeight: CGFloat = 620
    static var hairlineWidth: CGFloat { 1 / max(NSScreen.main?.backingScaleFactor ?? 2, 1) }
    static let sidebarMinWidth: CGFloat = 286
    static let sidebarIdealWidth: CGFloat = 328
    static let sidebarMaxWidth: CGFloat = 390
    static let compactSidebarWidth: CGFloat = 64
    static let inspectorWidth: CGFloat = 284
    static let threadPanelWidth: CGFloat = 360
    static var threadPanelDockWidth: CGFloat { threadPanelWidth + hairlineWidth }
    static let transcriptMaxBubbleWidth: CGFloat = 560
    static let compactTranscriptMaxBubbleWidth: CGFloat = 500
    static let composerMaxWidth: CGFloat = 720
    static let rowHeight: CGFloat = 68
}

enum I2Palette {
    // Surfaces carry a faint red wash so the whole window reads as intentionally
    // themed around the light-red accent rather than plain system gray with a
    // lone red highlight. Each surface resolves per light/dark appearance.
    static var appBackground: Color {
        dynamic(light: srgb(0.999, 0.991, 0.992), dark: srgb(0.110, 0.090, 0.094))
    }
    static var sidebarBackground: Color {
        dynamic(light: srgb(0.991, 0.967, 0.969), dark: srgb(0.145, 0.114, 0.120))
    }
    static var elevatedBackground: Color {
        dynamic(light: srgb(1.0, 0.980, 0.982), dark: srgb(0.170, 0.130, 0.137))
    }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var primaryText: Color { Color(nsColor: .labelColor) }
    static var secondaryText: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    static var selectionFill: Color { Color.accentColor.opacity(0.14) }
    static var outgoingBubble: Color { Color.accentColor.opacity(0.18) }
    static var incomingBubble: Color {
        dynamic(light: srgb(0.925, 0.878, 0.884), dark: srgb(0.243, 0.185, 0.196))
    }
    /// Hairline border that crisps up incoming bubbles against the warm surface.
    static var incomingBubbleBorder: Color {
        dynamic(light: srgb(0.878, 0.812, 0.820), dark: srgb(0.320, 0.250, 0.262))
    }
    static var warningFill: Color { Color(nsColor: .systemOrange).opacity(0.13) }
    static var errorFill: Color { Color(nsColor: .systemRed).opacity(0.12) }
    static var successFill: Color { Color(nsColor: .systemGreen).opacity(0.12) }
    static var infoFill: Color { Color.accentColor.opacity(0.11) }
    /// Vertical rail used to connect Slack-style reply threads.
    static var threadRail: Color { Color.accentColor.opacity(0.45) }

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

enum I2Motion {
    static func stateChange(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.28)
    }

    /// Spring used for overlays/panels appearing and disappearing.
    static func overlay(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)
    }

    /// Snappy, slightly-damped spring for the sidebar collapse/expand so the
    /// width glides to rest instead of easing linearly.
    static func sidebar(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88)
    }

    /// Docked thread panel reveal. The panel content stays fixed-width while
    /// the dock opens; no slide transition competes with transcript layout.
    static func threadPanel(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.19)
    }

    /// Quick cleanup when a partial swipe is released or cancelled.
    static func swipeReset(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.14)
    }

    /// Insertion/removal transition for floating overlays (Spotlight-style).
    static var overlayTransition: AnyTransition {
        .scale(scale: 0.97, anchor: .center).combined(with: .opacity)
    }
}

struct I2SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

struct I2Pill: View {
    let title: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct I2Divider: View {
    var body: some View {
        Rectangle()
            .fill(I2Palette.separator)
            .frame(height: I2Layout.hairlineWidth)
    }
}

struct I2VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(I2Palette.separator)
            .frame(width: I2Layout.hairlineWidth)
    }
}

import AppKit
import SwiftUI

enum I2Layout {
    static let minWindowWidth: CGFloat = 920
    static let minWindowHeight: CGFloat = 620
    static let sidebarMinWidth: CGFloat = 286
    static let sidebarIdealWidth: CGFloat = 328
    static let sidebarMaxWidth: CGFloat = 390
    static let inspectorWidth: CGFloat = 284
    static let transcriptMaxBubbleWidth: CGFloat = 560
    static let compactTranscriptMaxBubbleWidth: CGFloat = 500
    static let rowHeight: CGFloat = 68
}

enum I2Palette {
    static var appBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var sidebarBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var elevatedBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var primaryText: Color { Color(nsColor: .labelColor) }
    static var secondaryText: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    static var selectionFill: Color { Color.accentColor.opacity(0.14) }
    static var outgoingBubble: Color { Color.accentColor.opacity(0.18) }
    static var incomingBubble: Color { Color(nsColor: .controlBackgroundColor) }
    static var warningFill: Color { Color(nsColor: .systemOrange).opacity(0.13) }
    static var errorFill: Color { Color(nsColor: .systemRed).opacity(0.12) }
    static var successFill: Color { Color(nsColor: .systemGreen).opacity(0.12) }
    static var infoFill: Color { Color.accentColor.opacity(0.11) }
}

enum I2Motion {
    static func stateChange(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
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
            .frame(height: 1 / max(NSScreen.main?.backingScaleFactor ?? 2, 1))
    }
}

struct I2VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(I2Palette.separator)
            .frame(width: 1 / max(NSScreen.main?.backingScaleFactor ?? 2, 1))
    }
}

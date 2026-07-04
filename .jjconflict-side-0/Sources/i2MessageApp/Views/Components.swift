import SwiftUI
import i2MessageCore

struct AvatarView: View {
    let contact: Contact?
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(color(for: contact?.avatar?.colorSeed))

            Text(contact?.avatar?.initials ?? initials)
                .font(.system(size: max(size * 0.34, 10), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: String {
        guard let name = contact?.displayName, !name.isEmpty else {
            return "?"
        }

        return name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private func color(for seed: String?) -> Color {
        switch seed {
        case "amber":
            return .accentColor
        case "plum":
            return Color(red: 0.48, green: 0.31, blue: 0.62)
        case "blue":
            return Color(red: 0.20, green: 0.43, blue: 0.72)
        case "green":
            return Color(red: 0.24, green: 0.55, blue: 0.38)
        default:
            return .secondary
        }
    }
}

struct AvatarStack: View {
    let contacts: [Contact]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(contacts.prefix(3)) { contact in
                AvatarView(contact: contact, size: 34)
                    .overlay {
                        Circle().stroke(.background, lineWidth: 2)
                    }
            }
        }
        .frame(minWidth: 34, alignment: .leading)
        .accessibilityHidden(true)
    }
}

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: Capsule())
            .accessibilityLabel("\(count) unread")
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .padding(20)
        .accessibilityElement(children: .combine)
    }
}

struct ConversationSkeletonList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 10) {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(width: 160, height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 9)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            Spacer()
        }
        .accessibilityLabel("Loading conversations")
    }
}

struct MessageSkeletonList: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { index in
                HStack {
                    if index.isMultiple(of: 2) {
                        skeletonBubble(width: 240)
                        Spacer()
                    } else {
                        Spacer()
                        skeletonBubble(width: 320)
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .accessibilityLabel("Loading messages")
    }

    private func skeletonBubble(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.quaternary)
            .frame(width: width, height: 42)
    }
}

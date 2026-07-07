import AppKit
import AVFoundation
import SwiftUI
import i2MessageCore

/// Loads a downsized bitmap for an image or video attachment off the main
/// thread. Returns nil for non-media or unreadable files.
enum MediaThumbnail {
    static func load(_ attachment: MessageAttachment, maxDimension: CGFloat) async -> NSImage? {
        guard attachment.transferState == .local else { return nil }
        let source = attachment.thumbnailURL ?? attachment.fileURL
        guard let source else { return nil }
        let kind = attachment.kind
        return await Task.detached(priority: .utility) {
            switch kind {
            case .image, .sticker:
                guard let raw = NSImage(contentsOf: source) else { return nil }
                return downscale(raw, maxDimension: maxDimension)
            case .video:
                return videoFrame(source, maxDimension: maxDimension)
            default:
                return nil
            }
        }.value
    }

    private static func downscale(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension,
              size.width > 0, size.height > 0 else {
            return image
        }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let scaled = NSImage(size: target)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        scaled.unlockFocus()
        return scaled
    }

    private static func videoFrame(_ url: URL, maxDimension: CGFloat) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Inline image/video preview shown inside a message bubble. Falls back to the
/// filename chip for non-media, still-downloading, or unreadable attachments.
struct InlineAttachmentView: View {
    let attachment: MessageAttachment
    var maxWidth: CGFloat
    @State private var image: NSImage?
    @State private var loadFailed = false

    private var isRenderableMedia: Bool {
        (attachment.kind == .image || attachment.kind == .video || attachment.kind == .sticker)
            && attachment.transferState == .local
            && attachment.fileURL != nil
    }

    var body: some View {
        if isRenderableMedia, !loadFailed {
            preview
        } else {
            AttachmentChip(attachment: attachment)
        }
    }

    private var aspectRatio: CGFloat {
        if let dimensions = attachment.dimensions, dimensions.width > 0, dimensions.height > 0 {
            return CGFloat(dimensions.width) / CGFloat(dimensions.height)
        }
        if let image, image.size.height > 0 {
            return image.size.width / image.size.height
        }
        return 4.0 / 3.0
    }

    private var preview: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary.opacity(0.5))
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .frame(width: previewWidth, height: previewWidth / max(aspectRatio, 0.4))
        .frame(maxHeight: 340)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(alignment: .center) {
            if attachment.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture {
            if let url = attachment.fileURL { NSWorkspace.shared.open(url) }
        }
        .help(attachment.filename)
        .task(id: attachment.id) {
            let loaded = await MediaThumbnail.load(attachment, maxDimension: 1100)
            if let loaded {
                image = loaded
            } else {
                loadFailed = true
            }
        }
    }

    private var previewWidth: CGFloat {
        min(maxWidth, 300)
    }
}

struct AvatarView: View {
    @EnvironmentObject private var model: AppViewModel
    let contact: Contact?
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            if let contact,
               let data = model.contactThumbnails[contact.id],
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(color(for: contact?.avatar?.colorSeed))

                Text(contact?.avatar?.initials ?? initials)
                    .font(.system(size: max(size * 0.34, 10), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .frame(width: size, height: size)
        .task(id: contact?.id) {
            model.requestContactThumbnail(for: contact)
        }
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
            return Color(red: 0.18, green: 0.40, blue: 0.72)
        case "green":
            return Color(red: 0.20, green: 0.52, blue: 0.34)
        case "teal":
            return Color(red: 0.12, green: 0.52, blue: 0.54)
        case "rose":
            return Color(red: 0.70, green: 0.28, blue: 0.42)
        case "indigo":
            return Color(red: 0.30, green: 0.34, blue: 0.72)
        case "copper":
            return Color(red: 0.62, green: 0.36, blue: 0.20)
        default:
            return .secondary
        }
    }
}

struct AvatarStack: View {
    let contacts: [Contact]
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: -8) {
            ForEach(contacts.prefix(3)) { contact in
                AvatarView(contact: contact, size: size)
                    .overlay {
                        Circle().stroke(I2Palette.appBackground, lineWidth: 2)
                    }
            }
        }
        .frame(minWidth: size, alignment: .leading)
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
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(22)
        .accessibilityElement(children: .combine)
    }
}

struct StatusBannerView: View {
    let banner: StatusBanner
    var action: (() -> Void)?
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(banner.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle = banner.actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(action: dismiss) {
                Label("Dismiss", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch banner.tone {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch banner.tone {
        case .info:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var background: Color {
        switch banner.tone {
        case .info:
            return I2Palette.infoFill
        case .success:
            return I2Palette.successFill
        case .warning:
            return I2Palette.warningFill
        case .error:
            return I2Palette.errorFill
        }
    }
}

struct PermissionStateIcon: View {
    let state: PermissionState

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(color)
            .frame(width: 16)
            .accessibilityLabel(state.rawValue)
    }

    private var iconName: String {
        switch state {
        case .granted:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "exclamationmark.triangle.fill"
        case .notDetermined:
            return "circle.dashed"
        case .unsupported:
            return "slash.circle"
        }
    }

    private var color: Color {
        switch state {
        case .granted:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .secondary
        case .unsupported:
            return .orange
        }
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
                .frame(height: I2Layout.rowHeight)
                .padding(.horizontal, 14)
            }
            Spacer()
        }
        .accessibilityLabel("Loading conversations")
    }
}

struct MessageSkeletonList: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<9, id: \.self) { index in
                HStack {
                    if index.isMultiple(of: 2) {
                        skeletonBubble(width: index.isMultiple(of: 4) ? 250 : 340)
                        Spacer(minLength: 80)
                    } else {
                        Spacer(minLength: 80)
                        skeletonBubble(width: index.isMultiple(of: 3) ? 210 : 380)
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

struct AttachmentChip: View {
    let attachment: MessageAttachment

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(secondaryLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if attachment.transferState == .downloading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attachment \(attachment.filename), \(secondaryLabel)")
    }

    private var iconName: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .audio:
            return "waveform"
        case .file:
            return "doc"
        case .sticker:
            return "face.smiling"
        case .tapback:
            return "hand.thumbsup"
        case .unknown:
            return "paperclip"
        }
    }

    private var secondaryLabel: String {
        let size: String
        if let byteCount = attachment.byteCount {
            size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        } else if let dimensions = attachment.dimensions {
            size = "\(dimensions.width)x\(dimensions.height)"
        } else {
            size = attachment.kind.rawValue.capitalized
        }

        switch attachment.transferState {
        case .local:
            return size
        case .remotePlaceholder:
            return "\(size), in iCloud"
        case .downloading:
            return "\(size), downloading"
        case .failed:
            return "\(size), failed"
        }
    }
}

struct DraftAttachmentChip: View {
    let attachment: DraftAttachment
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
            Text(attachment.filename)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: remove) {
                Label("Remove \(attachment.filename)", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct ReactionCluster: View {
    let reactions: [MessageReaction]
    /// Resolves a reaction sender to a display name for the hover tooltip.
    var senderName: ((ContactID) -> String)?

    private struct ReactionGroup: Identifiable {
        var id: String
        var emoji: String
        var count: Int
        var title: String
        var senderIDs: [ContactID]
    }

    private var groups: [ReactionGroup] {
        var ordered: [ReactionGroup] = []
        for reaction in reactions {
            let emoji = ReactionCluster.emoji(for: reaction.kind, displayText: reaction.displayText)
            if let index = ordered.firstIndex(where: { $0.emoji == emoji }) {
                ordered[index].count += 1
                ordered[index].senderIDs.append(reaction.senderID)
            } else {
                ordered.append(
                    ReactionGroup(
                        id: emoji,
                        emoji: emoji,
                        count: 1,
                        title: ReactionCluster.title(for: reaction.kind),
                        senderIDs: [reaction.senderID]
                    )
                )
            }
        }
        return ordered
    }

    private func tooltip(for group: ReactionGroup) -> String {
        guard let senderName else {
            return "\(group.count) \(group.title)"
        }
        let names = group.senderIDs.map(senderName)
        return "\(group.title) — \(names.joined(separator: ", "))"
    }

    var body: some View {
        HStack(spacing: -5) {
            ForEach(groups) { group in
                HStack(spacing: 2) {
                    Text(group.emoji)
                        .font(.system(size: 11))
                    if group.count > 1 {
                        Text("\(group.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, group.count > 1 ? 7 : 5)
                .padding(.vertical, 4)
                .background(I2Palette.elevatedBackground, in: Capsule())
                .overlay {
                    Capsule().stroke(I2Palette.separator, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .help(tooltip(for: group))
                .accessibilityLabel(tooltip(for: group))
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func emoji(for kind: MessageReactionKind, displayText: String?) -> String {
        switch kind {
        case .loved:
            return "❤️"
        case .liked:
            return "👍"
        case .disliked:
            return "👎"
        case .laughed:
            return "😂"
        case .emphasized:
            return "‼️"
        case .questioned:
            return "❓"
        case .custom:
            return displayText ?? "💬"
        }
    }

    static func title(for kind: MessageReactionKind) -> String {
        switch kind {
        case .loved:
            return "Love"
        case .liked:
            return "Like"
        case .disliked:
            return "Dislike"
        case .laughed:
            return "Haha"
        case .emphasized:
            return "Emphasize"
        case .questioned:
            return "Question"
        case .custom:
            return "Reaction"
        }
    }
}

struct IndexingStatusView: View {
    let progress: IndexingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: progress.isIndexing ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                    .foregroundStyle(progress.isIndexing ? Color.accentColor : .green)
                Text("Local Search")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(progress.isIndexing ? "Indexing" : "Ready")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                labeledProgress("Exact", value: progress.exactProgress)
                labeledProgress("Semantic", value: progress.semanticProgress)
            }

            Text(progress.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func labeledProgress(_ label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            ProgressView(value: min(max(value, 0), 1))
                .controlSize(.mini)
            Text("\(Int(value * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

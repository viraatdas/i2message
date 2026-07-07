import AppKit
import SwiftUI
import i2MessageCore

/// Floating Cmd+I panel: participants, shared photos, and links for the
/// selected conversation. Content-driven, no chrome buttons.
struct InfoPanelView: View {
    @EnvironmentObject private var model: AppViewModel

    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 6)]

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { model.closeInfoPanel() }

            VStack(alignment: .leading, spacing: 0) {
                header
                I2Divider()
                content
            }
            .frame(width: 420)
            .frame(maxHeight: 560)
            .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 26, y: 18)
            .padding(.top, 70)
        }
        .onExitCommand { model.closeInfoPanel() }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let conversation = model.selectedConversation {
                AvatarStack(contacts: conversation.participants.filter { !$0.isCurrentUser }, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    let names = model.contactNames(for: conversation)
                    Text(names.isEmpty ? conversation.service.rawValue : names)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        switch model.infoPanelPhase {
        case .loading, .idle:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Gathering shared photos and links…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        case .empty:
            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No shared photos or links in this chat yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(20)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.infoPanelMedia.isEmpty {
                        sectionHeader("Photos & Videos", count: model.infoPanelMedia.count)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(model.infoPanelMedia) { attachment in
                                SharedMediaThumbnail(attachment: attachment)
                            }
                        }
                    }

                    if !model.infoPanelLinks.isEmpty {
                        sectionHeader("Links", count: model.infoPanelLinks.count)
                        VStack(spacing: 2) {
                            ForEach(model.infoPanelLinks) { link in
                                SharedLinkRow(link: link)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// A shared image/video thumbnail that loads its bitmap off the main thread and
/// opens the file on click.
private struct SharedMediaThumbnail: View {
    let attachment: MessageAttachment
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.6))
                    Image(systemName: attachment.kind == .video ? "video" : "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if attachment.kind == .video {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { open() }
        .help(attachment.filename)
        .task(id: attachment.id) { await loadThumbnail() }
    }

    private func open() {
        if let url = attachment.fileURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadThumbnail() async {
        let source = attachment.thumbnailURL ?? attachment.fileURL
        guard attachment.kind == .image, let source else { return }
        let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let raw = NSImage(contentsOf: source) else { return nil }
            let target = NSSize(width: 172, height: 172)
            let thumb = NSImage(size: target)
            thumb.lockFocus()
            raw.draw(in: NSRect(origin: .zero, size: target),
                     from: .zero, operation: .copy, fraction: 1)
            thumb.unlockFocus()
            return thumb
        }.value
        if let loaded { image = loaded }
    }
}

private struct SharedLinkRow: View {
    let link: SharedLink

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(link.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowHighlightButtonStyle())
    }
}

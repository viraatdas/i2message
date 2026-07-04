import SwiftUI
import i2MessageCore

struct ContactsWorkspaceView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Group {
            if let contact = model.selectedContact {
                HStack(spacing: 0) {
                    ContactDetailView(contact: contact)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                    I2Divider()
                        .frame(width: 1)

                    ContactConversationPane(contact: contact)
                        .frame(width: 330)
                }
            } else {
                EmptyStateView(
                    title: "Select a contact",
                    message: "Handles, shared conversations, permissions, and quick actions appear here.",
                    systemImage: "person.crop.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(I2Palette.appBackground)
    }
}

private struct ContactDetailView: View {
    @EnvironmentObject private var model: AppViewModel
    let contact: Contact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    AvatarView(contact: contact, size: 58)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.displayName)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        Text(contact.handles.first?.value ?? "No handle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        Task { await model.openConversation(with: contact) }
                    } label: {
                        Label("Message", systemImage: "message")
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 10) {
                    I2SectionLabel(title: "Handles")
                        .padding(.horizontal, -14)

                    ForEach(Array(contact.handles.enumerated()), id: \.offset) { _, handle in
                        HStack(spacing: 10) {
                            Image(systemName: handle.kind == .emailAddress ? "envelope" : "phone")
                                .frame(width: 18)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(handle.value)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("\(handle.service.rawValue) / \(handle.kind.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    I2SectionLabel(title: "Contact Quality")
                        .padding(.horizontal, -14)

                    HStack(spacing: 8) {
                        I2Pill(title: contact.lastResolvedAt == nil ? "Unresolved" : "Resolved", systemImage: "checkmark.seal", tint: contact.lastResolvedAt == nil ? .orange : .green)
                        I2Pill(title: "\(model.conversations(for: contact).count) threads", systemImage: "message", tint: .secondary)
                        I2Pill(title: "Local only", systemImage: "lock", tint: .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    I2SectionLabel(title: "Actions")
                        .padding(.horizontal, -14)

                    Button {
                        model.searchQuery = contact.displayName
                        model.searchConversationScope = nil
                        model.sidebarDestination = .search
                        Task { await model.performSearch(reset: true) }
                    } label: {
                        Label("Search messages with \(contact.displayName)", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await model.openConversation(with: contact) }
                    } label: {
                        Label("Open latest conversation", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

private struct ContactConversationPane: View {
    @EnvironmentObject private var model: AppViewModel
    let contact: Contact

    var body: some View {
        VStack(spacing: 0) {
            I2SectionLabel(title: "Shared Threads", trailing: "\(model.conversations(for: contact).count)")
            I2Divider()

            if model.conversations(for: contact).isEmpty {
                EmptyStateView(
                    title: "No conversations",
                    message: "Mock contact is ready, but no current thread exists.",
                    systemImage: "message.badge"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.conversations(for: contact)) { conversation in
                            Button {
                                Task { await model.selectConversation(conversation.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(conversation.title)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(conversation.lastMessage?.text ?? "No preview")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(I2Palette.sidebarBackground)
    }
}

private extension ContactHandleKind {
    var label: String {
        switch self {
        case .phoneNumber:
            return "Phone"
        case .emailAddress:
            return "Email"
        case .unknown:
            return "Handle"
        }
    }
}

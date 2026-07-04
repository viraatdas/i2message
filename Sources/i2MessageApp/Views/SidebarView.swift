import SwiftUI
import i2MessageCore

struct SidebarView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            I2Divider()

            switch model.sidebarDestination {
            case .conversations:
                conversationsList
            case .contacts:
                contactsList
            case .search:
                searchSummaryList
            }

            I2Divider()
            footer
        }
        .background(I2Palette.sidebarBackground)
        .onChange(of: model.focusRequest) { request in
            guard request == .sidebarSearch else { return }
            filterFocused = true
            model.consumeFocusRequest(.sidebarSearch)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(model.sidebarDestination.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    Task { await model.perform(.newMessage) }
                } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("New Message")
            }

            Picker("Sidebar", selection: $model.sidebarDestination) {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbolName)
                        .tag(destination)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $model.quickFilterText)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onSubmit {
                        if model.sidebarDestination == .search {
                            model.searchQuery = model.quickFilterText
                            Task { await model.performSearch(reset: true) }
                        }
                    }
                if !model.quickFilterText.isEmpty {
                    Button {
                        model.quickFilterText = ""
                    } label: {
                        Label("Clear filter", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var conversationsList: some View {
        VStack(spacing: 0) {
            Picker("Conversation Filter", selection: $model.conversationScope) {
                ForEach(ConversationScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if model.conversationPhase == .loading {
                ConversationSkeletonList()
            } else if model.filteredConversations.isEmpty {
                EmptyStateView(
                    title: "No conversations",
                    message: "Try another filter or search term.",
                    systemImage: "message"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredConversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == model.selectedConversationID
                            ) {
                                Task { await model.selectConversation(conversation.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var contactsList: some View {
        Group {
            if model.contactPhase == .loading {
                ConversationSkeletonList()
            } else if model.filteredContacts.isEmpty {
                EmptyStateView(
                    title: "No contacts",
                    message: "Try a name, phone number, or email address.",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredContacts) { contact in
                            ContactSidebarRow(
                                contact: contact,
                                isSelected: contact.id == model.selectedContactID
                            ) {
                                model.selectContact(contact.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var searchSummaryList: some View {
        VStack(spacing: 0) {
            I2SectionLabel(title: "Search", trailing: model.searchResultCountLabel)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Exact phrase or semantic intent", text: $model.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await model.performSearch(reset: true) }
                    }

                Picker("Mode", selection: $model.searchMode) {
                    Text("Exact").tag(SearchMode.exact)
                    Text("Semantic").tag(SearchMode.semantic)
                    Text("Hybrid").tag(SearchMode.hybrid)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.searchMode) { mode in
                    Task { await model.setSearchMode(mode) }
                }

                Button {
                    Task { await model.performSearch(reset: true) }
                } label: {
                    Label("Search", systemImage: model.searchMode == .semantic ? "sparkles" : "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            SearchMiniResults()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.orange)
                    Text("Offline cache")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
            }

            IndexingStatusView(progress: model.indexingProgress)
            PermissionsMiniFooter(snapshot: model.permissionSnapshot)
            ActionAvailabilityFooter(snapshot: model.actionAvailabilitySnapshot)
        }
        .padding(10)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                AvatarStack(contacts: conversation.participants.filter { !$0.isCurrentUser }, size: 34)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(conversation.title)
                            .font(.body.weight(conversation.unreadCount > 0 ? .semibold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if conversation.pinnedRank != nil {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if conversation.isMuted {
                            Image(systemName: "bell.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Text(conversation.lastMessage?.text ?? "No messages yet")
                        .font(.callout)
                        .foregroundStyle(conversation.unreadCount > 0 ? .primary : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        I2Pill(title: conversation.service.rawValue, tint: .secondary)

                        if conversation.lastMessage?.hasAttachments == true {
                            I2Pill(title: "File", systemImage: "paperclip", tint: .secondary)
                        }

                        Spacer(minLength: 4)

                        if conversation.unreadCount > 0 {
                            UnreadBadge(count: conversation.unreadCount)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: I2Layout.rowHeight, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? I2Palette.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let unread = conversation.unreadCount > 0 ? ", \(conversation.unreadCount) unread" : ""
        return "\(conversation.title), \(conversation.lastMessage?.text ?? "No messages")\(unread)"
    }
}

private struct ContactSidebarRow: View {
    let contact: Contact
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AvatarView(contact: contact, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(contact.handles.first?.value ?? "No handle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? I2Palette.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SearchMiniResults: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Group {
            if model.searchPhase == .loading {
                ConversationSkeletonList()
            } else if model.searchPhase == .idle {
                EmptyStateView(
                    title: "Search locally",
                    message: "Run exact phrase search or semantic search without leaving the app.",
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.searchMode == .semantic {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.semanticSnippets.prefix(8)) { snippet in
                            Button {
                                Task { await model.openSemanticSnippet(snippet) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(model.conversationTitle(for: snippet.conversationID))
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(Int(snippet.similarity * 100))%")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(snippet.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(9)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.exactSearchResults.prefix(10)) { result in
                            Button {
                                Task { await model.openSearchResult(result) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Text(result.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(9)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

private struct PermissionsMiniFooter: View {
    let snapshot: PermissionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(snapshot.statuses.prefix(3)) { status in
                HStack(spacing: 8) {
                    PermissionStateIcon(state: status.state)

                    Text(status.permission.displayName)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(status.state.shortLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct ActionAvailabilityFooter: View {
    let snapshot: MessagingActionAvailabilitySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text("Parity")
                    .font(.caption.weight(.medium))

                Spacer()

                Text("\(availableCount)/\(snapshot.statuses.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let attentionStatus {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: attentionStatus.state))
                        .foregroundStyle(color(for: attentionStatus.state))
                        .frame(width: 16)

                    Text(attentionStatus.kind.displayName)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(attentionStatus.state.shortLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }

    private var availableCount: Int {
        snapshot.statuses.filter { $0.state == .available }.count
    }

    private var attentionStatus: MessagingActionAvailability? {
        snapshot.statuses.first { $0.state != .available }
    }

    private func iconName(for state: MessagingActionAvailabilityState) -> String {
        switch state {
        case .available:
            return "checkmark.circle.fill"
        case .requiresPermission, .requiresUserHandoff, .degraded:
            return "exclamationmark.circle"
        case .unsupported:
            return "slash.circle"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    private func color(for state: MessagingActionAvailabilityState) -> Color {
        switch state {
        case .available:
            return .green
        case .requiresPermission, .requiresUserHandoff, .degraded:
            return .orange
        case .unsupported:
            return .secondary
        case .unavailable:
            return .red
        }
    }
}

private extension PermissionState {
    var shortLabel: String {
        switch self {
        case .notDetermined:
            return "Needed"
        case .granted:
            return "On"
        case .denied:
            return "Off"
        case .restricted:
            return "Limited"
        case .unsupported:
            return "N/A"
        }
    }
}

private extension MessagingActionAvailabilityState {
    var shortLabel: String {
        switch self {
        case .available:
            return "On"
        case .requiresPermission:
            return "Needs OK"
        case .requiresUserHandoff:
            return "Handoff"
        case .degraded:
            return "Partial"
        case .unsupported:
            return "N/A"
        case .unavailable:
            return "Off"
        }
    }
}

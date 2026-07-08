import SwiftUI
import i2MessageCore

/// Floating Spotlight-style search bar presented over the app content by
/// Cmd+Shift+P (all chats) and Cmd+F (current chat).
struct SearchOverlayView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var searchFocused: Bool
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    model.closeSearchOverlay()
                }

            VStack(spacing: 0) {
                searchField
                if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    I2Divider()
                    resultsList
                }
            }
            .frame(width: 640)
            .background(I2Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(I2Palette.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 26, y: 18)
            .offset(y: -40)
        }
        .onAppear {
            searchFocused = true
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
        }
        .onExitCommand {
            model.closeSearchOverlay()
        }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .searchField else { return }
            searchFocused = true
            model.consumeFocusRequest(.searchField)
        }
        .onChange(of: model.searchQuery) { _, _ in
            scheduleSearch()
        }
        .accessibilityElement(children: .contain)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: model.searchMode == .semantic ? "sparkles" : "magnifyingglass")
                .foregroundStyle(.secondary)

            if let scopedID = model.searchConversationScope {
                HStack(spacing: 4) {
                    Text(model.conversationTitle(for: scopedID))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Button {
                        model.searchConversationScope = nil
                        scheduleSearch(immediately: true)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Search all chats instead")
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .frame(maxWidth: 180, alignment: .leading)
            }

            TextField(
                model.searchConversationScope == nil ? "Search all messages and contacts" : "Search this chat",
                text: $model.searchQuery
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($searchFocused)
            .onSubmit {
                if let first = model.exactSearchResults.first {
                    Task { await model.openSearchResult(first) }
                } else if let snippet = model.semanticSnippets.first {
                    Task { await model.openSemanticSnippet(snippet) }
                }
            }

            Button {
                Task { await model.toggleSemanticSearch() }
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(model.searchMode == .semantic ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(model.searchMode == .semantic ? "Semantic search on (⌘⇧K)" : "Try semantic search (⌘⇧K)")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !model.searchContactMatches.isEmpty {
                    OverlaySectionHeader(title: "Contacts")
                    ForEach(model.searchContactMatches) { contact in
                        OverlayContactRow(contact: contact)
                    }
                }

                messagesSection
            }
            .padding(8)
        }
        .frame(maxHeight: 420)
    }

    @ViewBuilder
    private var messagesSection: some View {
        switch model.searchPhase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching locally…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        case .empty:
            if model.searchContactMatches.isEmpty {
                Text("No matches. Try fewer words or semantic search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
        case .idle, .loaded:
            if model.searchMode == .semantic, !model.semanticSnippets.isEmpty {
                OverlaySectionHeader(title: "Messages")
                ForEach(model.semanticSnippets.prefix(12)) { snippet in
                    OverlaySnippetRow(snippet: snippet)
                }
            } else if !model.exactSearchResults.isEmpty {
                OverlaySectionHeader(title: "Messages")
                ForEach(model.exactSearchResults.prefix(12)) { result in
                    OverlayResultRow(result: result)
                }
            }
        }
    }

    private func scheduleSearch(immediately: Bool = false) {
        debounceTask?.cancel()
        let query = model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return
        }
        debounceTask = Task {
            if !immediately {
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            guard !Task.isCancelled else { return }
            await model.performSearch(reset: true)
        }
    }
}

private struct OverlaySectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

private struct OverlayContactRow: View {
    @EnvironmentObject private var model: AppViewModel
    let contact: Contact

    var body: some View {
        Button {
            Task { await model.openSearchContact(contact) }
        } label: {
            HStack(spacing: 11) {
                AvatarView(contact: contact, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let handle = contact.handles.first {
                        Text(handle.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(RowHighlightButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open chat with \(contact.displayName)")
    }
}

private struct OverlayResultRow: View {
    @EnvironmentObject private var model: AppViewModel
    let result: SearchResult

    var body: some View {
        Button {
            Task { await model.openSearchResult(result) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(result.snippet.isEmpty ? result.subtitle : result.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let date = result.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch result.kind {
        case .message:
            return "text.bubble"
        case .conversation:
            return "message"
        case .contact:
            return "person.crop.circle"
        case .attachment:
            return "paperclip"
        case .semanticSnippet:
            return "sparkles"
        }
    }
}

private struct OverlaySnippetRow: View {
    @EnvironmentObject private var model: AppViewModel
    let snippet: SemanticSnippet

    var body: some View {
        Button {
            Task { await model.openSemanticSnippet(snippet) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.conversationTitle(for: snippet.conversationID))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(snippet.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text("\(Int(snippet.similarity * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

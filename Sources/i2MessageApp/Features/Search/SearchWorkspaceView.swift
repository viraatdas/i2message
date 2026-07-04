import SwiftUI
import i2MessageCore

struct SearchWorkspaceView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            I2Divider()
            searchBody
        }
        .background(I2Palette.appBackground)
        .onChange(of: model.focusRequest) { _, request in
            guard request == .searchField else { return }
            searchFocused = true
            model.consumeFocusRequest(.searchField)
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search")
                        .font(.title2.weight(.semibold))
                    Text("Exact matches, local semantic snippets, and result previews.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Picker("Mode", selection: $model.searchMode) {
                    Text("Exact").tag(SearchMode.exact)
                    Text("Semantic").tag(SearchMode.semantic)
                    Text("Hybrid").tag(SearchMode.hybrid)
                }
                .pickerStyle(.segmented)
                .frame(width: 270)
                .onChange(of: model.searchMode) { _, mode in
                    Task { await model.setSearchMode(mode) }
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: model.searchMode == .semantic ? "sparkles" : "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search messages, contacts, attachments, or meaning", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit {
                            Task { await model.performSearch(reset: true) }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Menu {
                    Button("All Conversations") {
                        model.searchConversationScope = nil
                        Task { await model.performSearch(reset: true) }
                    }

                    Divider()

                    ForEach(model.filteredConversations.prefix(12)) { conversation in
                        Button(conversation.title) {
                            model.searchConversationScope = conversation.id
                            Task { await model.performSearch(reset: true) }
                        }
                    }
                } label: {
                    Label(scopeLabel, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.button)
                .frame(minWidth: 150)

                Button {
                    Task { await model.performSearch(reset: true) }
                } label: {
                    Label("Search", systemImage: "return")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                I2Pill(title: "\(model.searchResultCountLabel) results", systemImage: "number", tint: .secondary)
                if let scoped = model.searchConversationScope {
                    I2Pill(title: model.conversationTitle(for: scoped), systemImage: "message", tint: .accentColor)
                }
                I2Pill(title: model.searchMode == .semantic ? "Local semantic" : model.searchMode == .hybrid ? "Exact + semantic" : "Exact FTS-ready", systemImage: model.searchMode == .semantic ? "sparkles" : "magnifyingglass", tint: .secondary)
                Spacer()
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var searchBody: some View {
        switch model.searchPhase {
        case .idle:
            EmptyStateView(
                title: "Search your message history",
                message: "Use exact search for names, phrases, files, and timestamps. Use semantic search when you remember the idea but not the wording.",
                systemImage: "magnifyingglass"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            MessageSkeletonList()
        case .empty:
            EmptyStateView(
                title: "No results",
                message: "Try fewer words, a different scope, or semantic mode.",
                systemImage: "magnifyingglass.circle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyStateView(
                title: "Search unavailable",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Retry"
            ) {
                Task { await model.performSearch(reset: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            resultsView
        }
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if model.searchMode == .hybrid && !model.semanticSnippets.isEmpty {
                    I2SectionLabel(title: "Semantic Suggestions", trailing: "\(model.semanticSnippets.count)")
                        .padding(.horizontal, -14)
                    ForEach(model.semanticSnippets) { snippet in
                        SemanticSnippetResultRow(snippet: snippet)
                    }
                    I2Divider()
                        .padding(.vertical, 4)
                }

                if model.searchMode == .semantic {
                    I2SectionLabel(title: "Semantic Results", trailing: "\(model.semanticSnippets.count)")
                        .padding(.horizontal, -14)
                    ForEach(model.semanticSnippets) { snippet in
                        SemanticSnippetResultRow(snippet: snippet)
                    }
                } else {
                    I2SectionLabel(title: "Exact Results", trailing: "\(model.exactSearchResults.count)")
                        .padding(.horizontal, -14)
                    ForEach(model.exactSearchResults) { result in
                        SearchResultRow(result: result)
                    }

                    if model.searchHasMore {
                        HStack {
                            Spacer()
                            Button {
                                Task { await model.loadMoreSearchResults() }
                            } label: {
                                Label("Load More Results", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var scopeLabel: String {
        guard let scope = model.searchConversationScope else {
            return "All"
        }
        return model.conversationTitle(for: scope)
    }
}

private struct SearchResultRow: View {
    @EnvironmentObject private var model: AppViewModel
    let result: SearchResult

    var body: some View {
        Button {
            Task { await model.openSearchResult(result) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(result.kind == .semanticSnippet ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(result.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        I2Pill(title: result.kind.rawValue, tint: .secondary)

                        Spacer()

                        if let date = result.date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HighlightedSnippet(text: result.snippet, ranges: result.matchedRanges)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct SemanticSnippetResultRow: View {
    @EnvironmentObject private var model: AppViewModel
    let snippet: SemanticSnippet

    var body: some View {
        Button {
            Task { await model.openSemanticSnippet(snippet) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.conversationTitle(for: snippet.conversationID))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        I2Pill(title: "\(Int(snippet.similarity * 100))%", systemImage: "gauge.medium", tint: .accentColor)
                    }

                    Text(snippet.text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(4)

                    HStack(spacing: 8) {
                        Text("\(snippet.sourceMessageIDs.count) source messages")
                        Text(snippet.embeddingModelIdentifier)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(I2Palette.infoFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct HighlightedSnippet: View {
    let text: String
    let ranges: [i2MessageCore.TextRange]

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var attributed = AttributedString(text)
        guard let first = ranges.first,
              first.location >= 0,
              first.length > 0,
              first.location + first.length <= text.count else {
            return attributed
        }
        let start = attributed.characters.index(attributed.startIndex, offsetBy: first.location)
        let end = attributed.characters.index(start, offsetBy: first.length)
        attributed[start..<end].backgroundColor = Color.accentColor.opacity(0.24)
        attributed[start..<end].foregroundColor = .primary
        return attributed
    }
}

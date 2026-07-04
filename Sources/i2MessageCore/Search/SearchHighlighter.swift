import Foundation

enum SearchHighlighter {
    static func snippet(
        title: String,
        subtitle: String,
        body: String,
        query: String,
        maximumLength: Int = 180
    ) -> (text: String, ranges: [TextRange]) {
        let tokens = SearchTokenizer.uniqueTokenValues(in: query)
        let candidates = [body, title, subtitle].filter { !$0.isEmpty }
        let source = candidates.first { text in
            containsAnyToken(text, tokens: tokens)
        } ?? candidates.first ?? ""

        guard !source.isEmpty else {
            return ("", [])
        }

        let snippet = clippedSnippet(from: source, tokens: tokens, maximumLength: maximumLength)
        let ranges = matchedRanges(in: snippet, tokens: tokens)
        return (snippet, ranges)
    }

    private static func containsAnyToken(_ text: String, tokens: [String]) -> Bool {
        let normalized = SearchTokenizer.normalized(text)
        return tokens.contains { normalized.contains($0) }
    }

    private static func clippedSnippet(from text: String, tokens: [String], maximumLength: Int) -> String {
        guard text.count > maximumLength else {
            return text
        }

        let normalized = SearchTokenizer.normalized(text)
        let firstMatchOffset = tokens
            .compactMap { token -> Int? in
                guard let range = normalized.range(of: token) else {
                    return nil
                }
                return normalized.distance(from: normalized.startIndex, to: range.lowerBound)
            }
            .min() ?? 0

        let leadingContext = maximumLength / 4
        let startOffset = max(0, firstMatchOffset - leadingContext)
        let endOffset = min(text.count, startOffset + maximumLength)
        let startIndex = text.index(text.startIndex, offsetBy: startOffset)
        let endIndex = text.index(text.startIndex, offsetBy: endOffset)
        var clipped = String(text[startIndex..<endIndex])

        if startOffset > 0 {
            clipped = "..." + clipped
        }

        if endOffset < text.count {
            clipped += "..."
        }

        return clipped
    }

    private static func matchedRanges(in snippet: String, tokens: [String]) -> [TextRange] {
        guard !snippet.isEmpty, !tokens.isEmpty else {
            return []
        }

        let normalizedSnippet = SearchTokenizer.normalized(snippet)
        var ranges: [TextRange] = []

        for token in tokens {
            var searchStart = normalizedSnippet.startIndex
            while searchStart < normalizedSnippet.endIndex,
                  let range = normalizedSnippet.range(of: token, range: searchStart..<normalizedSnippet.endIndex) {
                let location = normalizedSnippet.distance(from: normalizedSnippet.startIndex, to: range.lowerBound)
                let length = normalizedSnippet.distance(from: range.lowerBound, to: range.upperBound)
                ranges.append(TextRange(location: location, length: length))
                searchStart = range.upperBound
            }
        }

        return ranges
            .sorted { left, right in
                if left.location == right.location {
                    return left.length > right.length
                }
                return left.location < right.location
            }
            .reduce(into: []) { partialResult, range in
                guard let last = partialResult.last else {
                    partialResult.append(range)
                    return
                }

                if range.location >= last.location + last.length {
                    partialResult.append(range)
                }
            }
    }
}

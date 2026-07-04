import Foundation

public struct SearchToken: Hashable, Sendable {
    public var value: String
    public var original: String

    public init(value: String, original: String) {
        self.value = value
        self.original = original
    }
}

public enum SearchTokenizer {
    public static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    public static func tokens(in value: String) -> [SearchToken] {
        let normalizedValue = normalized(value)
        var tokens: [SearchToken] = []
        var current = ""

        for scalar in normalizedValue.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                appendToken(&tokens, current)
                current.removeAll(keepingCapacity: true)
            }
        }

        appendToken(&tokens, current)
        return tokens
    }

    public static func uniqueTokenValues(in value: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for token in tokens(in: value) where seen.insert(token.value).inserted {
            ordered.append(token.value)
        }

        return ordered
    }

    static func fts5Query(for value: String) -> String? {
        let terms = uniqueTokenValues(in: value)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }

        guard !terms.isEmpty else {
            return nil
        }

        return terms.joined(separator: " AND ")
    }

    private static func appendToken(_ tokens: inout [SearchToken], _ value: String) {
        guard value.count >= 2 else {
            return
        }

        tokens.append(SearchToken(value: value, original: value))
    }
}

import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public protocol SemanticEmbeddingProviding: Sendable {
    var modelIdentifier: String { get }
    var dimension: Int { get }
    func embedding(for text: String) async throws -> [Float]
}

public final class AutomaticLocalSemanticEmbedder: SemanticEmbeddingProviding, @unchecked Sendable {
    public let fallback: HashingSemanticEmbedder

    public var modelIdentifier: String {
        appleSentenceEmbeddingAvailable ? "apple-natural-language-sentence-or-\(fallback.modelIdentifier)" : fallback.modelIdentifier
    }

    public var dimension: Int {
        #if canImport(NaturalLanguage)
        if let embedding = appleSentenceEmbedding {
            return embedding.dimension
        }
        #endif
        return fallback.dimension
    }

    #if canImport(NaturalLanguage)
    private let appleSentenceEmbedding: NLEmbedding?
    private var appleSentenceEmbeddingAvailable: Bool {
        appleSentenceEmbedding != nil
    }
    #else
    private let appleSentenceEmbeddingAvailable = false
    #endif

    public init(fallback: HashingSemanticEmbedder = HashingSemanticEmbedder()) {
        self.fallback = fallback
        #if canImport(NaturalLanguage)
        self.appleSentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        #endif
    }

    public func embedding(for text: String) async throws -> [Float] {
        #if canImport(NaturalLanguage)
        if let vector = appleSentenceEmbedding?.vector(for: text), !vector.isEmpty {
            return SemanticVector.normalized(vector.map(Float.init))
        }
        #endif
        return try await fallback.embedding(for: text)
    }
}

public struct HashingSemanticEmbedder: SemanticEmbeddingProviding {
    public var dimension: Int
    public var modelIdentifier: String

    private let synonymGroups: [[String]]

    public init(dimension: Int = 128, modelIdentifier: String = "local-hashing-semantic-v1") {
        self.dimension = max(32, dimension)
        self.modelIdentifier = modelIdentifier
        self.synonymGroups = [
            ["search", "find", "lookup", "query"],
            ["fast", "quick", "speed", "responsive", "snappy"],
            ["message", "text", "chat", "conversation"],
            ["photo", "image", "picture", "screenshot"],
            ["receipt", "invoice", "bill", "expense"],
            ["lunch", "dinner", "meal", "food", "eat"],
            ["coffee", "cafe", "espresso", "drink"],
            ["meeting", "sync", "call", "review"],
            ["trip", "flight", "travel", "airport"],
            ["bug", "crash", "broken", "issue"]
        ]
    }

    public func embedding(for text: String) async throws -> [Float] {
        var vector = Array(repeating: Float(0), count: dimension)
        let tokens = SearchTokenizer.uniqueTokenValues(in: text)

        for token in tokens {
            add(token, weight: 1, to: &vector)
            for synonym in synonyms(for: token) {
                add(synonym, weight: 0.55, to: &vector)
            }
        }

        for bigram in zip(tokens, tokens.dropFirst()).map({ "\($0.0)_\($0.1)" }) {
            add(bigram, weight: 0.75, to: &vector)
        }

        return SemanticVector.normalized(vector)
    }

    private func add(_ token: String, weight: Float, to vector: inout [Float]) {
        let hash = StableHash.digest(token)
        let unsigned = UInt64(hash, radix: 16) ?? 0
        let index = Int(unsigned % UInt64(dimension))
        let sign: Float = (unsigned & 1) == 0 ? 1 : -1
        vector[index] += sign * weight
    }

    private func synonyms(for token: String) -> [String] {
        guard let group = synonymGroups.first(where: { $0.contains(token) }) else {
            return []
        }

        return group.filter { $0 != token }
    }
}

enum SemanticVector {
    static func normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + ($1 * $1) })
        guard magnitude > 0 else {
            return vector
        }

        return vector.map { $0 / magnitude }
    }

    static func cosine(_ left: [Float], _ right: [Float]) -> Double {
        let count = min(left.count, right.count)
        guard count > 0 else {
            return 0
        }

        var dot = Float(0)
        for index in 0..<count {
            dot += left[index] * right[index]
        }

        return Double(dot)
    }

    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    static func decode(_ data: Data, dimension: Int) -> [Float] {
        let expectedBytes = dimension * MemoryLayout<Float>.size
        guard data.count >= expectedBytes else {
            return []
        }

        return data.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Float.self)
            return Array(buffer.prefix(dimension))
        }
    }
}

import Foundation

public enum AppTheme: String, Codable, Hashable, Sendable {
    case system
    case light
    case dark
}

public enum TranscriptDensity: String, Codable, Hashable, Sendable {
    case comfortable
    case compact
}

public struct SearchIndexSettings: Codable, Hashable, Sendable {
    public var exactIndexEnabled: Bool
    public var semanticIndexEnabled: Bool
    public var semanticModelIdentifier: String?
    public var indexAttachments: Bool

    public init(
        exactIndexEnabled: Bool = true,
        semanticIndexEnabled: Bool = true,
        semanticModelIdentifier: String? = nil,
        indexAttachments: Bool = true
    ) {
        self.exactIndexEnabled = exactIndexEnabled
        self.semanticIndexEnabled = semanticIndexEnabled
        self.semanticModelIdentifier = semanticModelIdentifier
        self.indexAttachments = indexAttachments
    }
}

public struct PrivacySettings: Codable, Hashable, Sendable {
    public var allowExternalEmbeddingProviders: Bool
    public var redactLogs: Bool

    public init(
        allowExternalEmbeddingProviders: Bool = false,
        redactLogs: Bool = true
    ) {
        self.allowExternalEmbeddingProviders = allowExternalEmbeddingProviders
        self.redactLogs = redactLogs
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var theme: AppTheme
    public var transcriptDensity: TranscriptDensity
    public var pageSize: Int
    public var launchAtLogin: Bool
    public var search: SearchIndexSettings
    public var privacy: PrivacySettings

    public init(
        theme: AppTheme = .system,
        transcriptDensity: TranscriptDensity = .comfortable,
        pageSize: Int = 50,
        launchAtLogin: Bool = false,
        search: SearchIndexSettings = SearchIndexSettings(),
        privacy: PrivacySettings = PrivacySettings()
    ) {
        self.theme = theme
        self.transcriptDensity = transcriptDensity
        self.pageSize = pageSize
        self.launchAtLogin = launchAtLogin
        self.search = search
        self.privacy = privacy
    }
}

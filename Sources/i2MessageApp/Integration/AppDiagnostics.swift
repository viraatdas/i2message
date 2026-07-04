import Foundation
import OSLog

enum AppDiagnostics {
    private static let logger = Logger(subsystem: "dev.viraat.i2message", category: "app")

    static func lifecycle(_ event: String) {
        logger.info("lifecycle event=\(event, privacy: .public)")
    }

    static func loadCompleted(duration: Duration, conversations: Int, contacts: Int, live: Bool) {
        logger.info(
            "load completed duration=\(duration.description, privacy: .public) conversations=\(conversations, privacy: .public) contacts=\(contacts, privacy: .public) live=\(live, privacy: .public)"
        )
    }

    static func operation(_ name: String, state: String) {
        logger.info("operation name=\(name, privacy: .public) state=\(state, privacy: .public)")
    }

    static func failure(_ name: String, category: String) {
        logger.error("failure name=\(name, privacy: .public) category=\(category, privacy: .public)")
    }
}

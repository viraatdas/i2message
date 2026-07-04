import Foundation

public protocol MessagesChangeMonitoring: Sendable {
    func changes() -> AsyncThrowingStream<MessagesChangeToken, Error>
}

public struct PollingMessagesChangeMonitor: MessagesChangeMonitoring {
    private let store: ReadOnlyMessagesStore
    private let pollInterval: TimeInterval

    public init(store: ReadOnlyMessagesStore, pollInterval: TimeInterval = 2) {
        self.store = store
        self.pollInterval = max(0.5, pollInterval)
    }

    public func changes() -> AsyncThrowingStream<MessagesChangeToken, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastToken: MessagesChangeToken?

                while !Task.isCancelled {
                    let token = await store.currentChangeToken()
                    if token != lastToken {
                        continuation.yield(token)
                        lastToken = token
                    }

                    let nanoseconds = UInt64(pollInterval * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

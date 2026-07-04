import Foundation

public struct MessageHandle: Hashable, Sendable {
    public var rowID: Int64?
    public var value: String
    public var service: MessageService

    public init(rowID: Int64? = nil, value: String, service: MessageService = .unknown) {
        self.rowID = rowID
        self.value = value
        self.service = service
    }
}

public protocol ContactResolving: Sendable {
    func contact(for handle: MessageHandle) async throws -> Contact
    func contacts(for handles: [MessageHandle]) async throws -> [MessageHandle: Contact]
    func contactID(for handle: MessageHandle) async throws -> ContactID
}

public actor FallbackContactResolver: ContactResolving {
    public init() {}

    public func contact(for handle: MessageHandle) async throws -> Contact {
        let contactHandle = ContactHandleNormalizer.contactHandle(value: handle.value, service: handle.service)
        return Contact.fallback(handle: contactHandle, handleRowID: handle.rowID)
    }

    public func contacts(for handles: [MessageHandle]) async throws -> [MessageHandle: Contact] {
        var contactsByHandle: [MessageHandle: Contact] = [:]
        contactsByHandle.reserveCapacity(handles.count)

        for handle in handles {
            contactsByHandle[handle] = try await contact(for: handle)
        }

        return contactsByHandle
    }

    public func contactID(for handle: MessageHandle) async throws -> ContactID {
        try await contact(for: handle).id
    }
}

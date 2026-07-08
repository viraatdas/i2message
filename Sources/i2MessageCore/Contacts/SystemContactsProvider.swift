import Contacts
import Foundation

public protocol ContactPhotoProviding: Sendable {
    func thumbnailData(for contactID: ContactID) async throws -> Data?
}

public actor SystemContactsProvider: ContactProviding, ContactResolving, ContactPhotoProviding {
    private let store: CNContactStore
    private let now: @Sendable () -> Date
    private var contactsByID: [ContactID: Contact] = [:]
    private var contactsByNormalizedHandle: [String: Contact] = [:]
    private var thumbnailDataByID: [ContactID: Data] = [:]
    private var hasLoadedIndex = false
    private let fallbackResolver = FallbackContactResolver()

    public init(store: CNContactStore = CNContactStore(), now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func contacts(matching query: String, page: PageRequest) async throws -> Page<Contact> {
        try Task.checkCancellation()
        try await ensureAuthorized()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = ContactCursor.decode(page.cursor) ?? 0
        let limit = max(1, min(page.limit, 200))
        let contacts = try loadContacts(matching: trimmedQuery)
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        let pageItems = Array(contacts.dropFirst(offset).prefix(limit))
        let nextOffset = offset + pageItems.count

        return Page(
            items: pageItems,
            nextCursor: nextOffset < contacts.count ? ContactCursor.encode(offset: nextOffset) : nil,
            previousCursor: offset > 0 ? ContactCursor.encode(offset: max(0, offset - limit)) : nil,
            hasMore: nextOffset < contacts.count,
            totalCount: contacts.count
        )
    }

    public func contact(id: ContactID) async throws -> Contact {
        try Task.checkCancellation()
        try await ensureAuthorized()
        try loadAllContactsIfNeeded()

        guard let contact = contactsByID[id] else {
            throw I2MessageError.notFound(resource: "Contact", id: id.rawValue)
        }

        return contact
    }

    public func contact(for handle: MessageHandle) async throws -> Contact {
        try Task.checkCancellation()

        // On first run the status is `.notDetermined`; request access here so
        // participant/sender resolution can surface real names instead of
        // silently falling back to raw phone-number handles.
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await requestContactsAccess()
        }

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return try await fallbackResolver.contact(for: handle)
        }

        try loadAllContactsIfNeeded()
        let contactHandle = ContactHandleNormalizer.contactHandle(value: handle.value, service: handle.service)

        if let contact = contactsByNormalizedHandle[contactHandle.normalizedValue] {
            return contact
        }

        return Contact.fallback(handle: contactHandle, handleRowID: handle.rowID, resolvedAt: now())
    }

    public func contacts(for handles: [MessageHandle]) async throws -> [MessageHandle: Contact] {
        var resolved: [MessageHandle: Contact] = [:]
        resolved.reserveCapacity(handles.count)

        for handle in handles {
            resolved[handle] = try await contact(for: handle)
        }

        return resolved
    }

    public func contactID(for handle: MessageHandle) async throws -> ContactID {
        try await contact(for: handle).id
    }

    public func thumbnailData(for contactID: ContactID) async throws -> Data? {
        try Task.checkCancellation()

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            throw I2MessageError.permissionDenied(.contacts, reason: "Contacts access is required to load contact photos.")
        }

        try loadAllContactsIfNeeded()
        return thumbnailDataByID[contactID]
    }

    private func ensureAuthorized() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return
        case .notDetermined:
            let granted = try await requestContactsAccess()
            guard granted else {
                throw I2MessageError.permissionDenied(.contacts, reason: "Contacts access was not granted.")
            }
        case .denied:
            throw I2MessageError.permissionDenied(.contacts, reason: "Contacts access is denied in System Settings.")
        case .restricted:
            throw I2MessageError.permissionDenied(.contacts, reason: "Contacts access is restricted on this Mac.")
        @unknown default:
            throw I2MessageError.permissionDenied(.contacts, reason: "Contacts access is unavailable.")
        }
    }

    private func requestContactsAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: I2MessageError.permissionDenied(.contacts, reason: error.localizedDescription))
                    return
                }

                continuation.resume(returning: granted)
            }
        }
    }

    private func loadContacts(matching query: String) throws -> [Contact] {
        if query.isEmpty {
            try loadAllContactsIfNeeded()
            return Array(contactsByID.values)
        }

        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: Self.keysToFetch())
        return contacts.map(mapContact)
    }

    private func loadAllContactsIfNeeded() throws {
        guard !hasLoadedIndex else {
            return
        }

        var indexedContactsByID: [ContactID: Contact] = [:]
        var indexedContactsByHandle: [String: Contact] = [:]
        var indexedThumbnails: [ContactID: Data] = [:]

        let request = CNContactFetchRequest(keysToFetch: Self.keysToFetch())
        request.sortOrder = .userDefault

        try store.enumerateContacts(with: request) { cnContact, _ in
            let contact = self.mapContact(cnContact)
            indexedContactsByID[contact.id] = contact

            if let thumbnail = cnContact.thumbnailImageData {
                indexedThumbnails[contact.id] = thumbnail
            }

            for handle in contact.handles {
                indexedContactsByHandle[handle.normalizedValue] = contact
            }
        }

        contactsByID = indexedContactsByID
        contactsByNormalizedHandle = indexedContactsByHandle
        thumbnailDataByID = indexedThumbnails
        hasLoadedIndex = true
    }

    private func mapContact(_ cnContact: CNContact) -> Contact {
        // CNContact raises an uncatchable NSException when the formatter asks
        // for a key that wasn't fetched, so only use it when every required
        // key is verifiably present; otherwise compose the name by hand.
        let formatterKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        let formattedName = cnContact.areKeysAvailable([formatterKeys])
            ? CNContactFormatter.string(from: cnContact, style: .fullName)
            : nil
        let displayName = formattedName
            ?? [cnContact.givenName, cnContact.middleName, cnContact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        let organizationFallback = displayName.isEmpty ? cnContact.organizationName : displayName
        let resolvedDisplayName = organizationFallback.isEmpty ? "Unknown Contact" : organizationFallback

        var handles: [ContactHandle] = []
        handles.reserveCapacity(cnContact.phoneNumbers.count + cnContact.emailAddresses.count)

        for phone in cnContact.phoneNumbers {
            handles.append(
                ContactHandleNormalizer.contactHandle(
                    value: phone.value.stringValue,
                    service: .unknown,
                    kind: .phoneNumber
                )
            )
        }

        for email in cnContact.emailAddresses {
            handles.append(
                ContactHandleNormalizer.contactHandle(
                    value: String(email.value),
                    service: .unknown,
                    kind: .emailAddress
                )
            )
        }

        return Contact(
            id: ContactID(rawValue: "contact:\(cnContact.identifier)"),
            displayName: resolvedDisplayName,
            handles: handles,
            avatar: ContactAvatar(
                initials: ContactInitials.initials(for: resolvedDisplayName),
                colorSeed: cnContact.identifier,
                imageURL: nil
            ),
            lastResolvedAt: now()
        )
    }

    private static func keysToFetch() -> [CNKeyDescriptor] {
        [
            // Everything CNContactFormatter needs (name order, contact type,
            // phonetic fields, …) — omitting it makes the formatter raise.
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
    }
}

private enum ContactCursor {
    private static let prefix = "contacts:v1:"

    static func encode(offset: Int) -> PageCursor {
        PageCursor(rawValue: "\(prefix)\(offset)")
    }

    static func decode(_ cursor: PageCursor?) -> Int? {
        guard let rawValue = cursor?.rawValue, rawValue.hasPrefix(prefix) else {
            return nil
        }

        return Int(rawValue.dropFirst(prefix.count))
    }
}

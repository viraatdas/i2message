import Foundation

public enum ContactHandleNormalizer {
    public static func normalizedValue(_ value: String, kind: ContactHandleKind? = nil) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKind = kind ?? handleKind(for: trimmed)

        switch resolvedKind {
        case .emailAddress:
            return trimmed.lowercased()
        case .phoneNumber:
            return normalizedPhoneNumber(trimmed)
        case .unknown:
            return trimmed.lowercased()
        }
    }

    public static func handleKind(for value: String) -> ContactHandleKind {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") {
            return .emailAddress
        }

        let digits = trimmed.filter(\.isNumber)
        if digits.count >= 7 {
            return .phoneNumber
        }

        return .unknown
    }

    public static func contactHandle(
        value: String,
        service: MessageService = .unknown,
        kind: ContactHandleKind? = nil
    ) -> ContactHandle {
        let resolvedKind = kind ?? handleKind(for: value)
        return ContactHandle(
            value: value,
            normalizedValue: normalizedValue(value, kind: resolvedKind),
            kind: resolvedKind,
            service: service
        )
    }

    private static func normalizedPhoneNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)

        guard !digits.isEmpty else {
            return trimmed.lowercased()
        }

        // Match on the national number so E.164 handles from chat.db
        // ("+15551234567") reconcile with Contacts entries stored without a
        // country code ("(555) 123-4567"). Both sides collapse to the last ten
        // significant digits, which is stable across the common formatting
        // variations we see between the two data sources.
        if digits.count > 10 {
            return String(digits.suffix(10))
        }
        return digits
    }
}

extension Contact {
    /// Returns the address-book contact with the exact chat.db handle first.
    /// This preserves which of several phone numbers belongs to an SMS thread
    /// and carries its real service into Messages Automation.
    func prioritizing(messageHandle: MessageHandle) -> Contact {
        let preferred = ContactHandleNormalizer.contactHandle(
            value: messageHandle.value,
            service: messageHandle.service
        )
        var result = self
        result.handles = [preferred] + handles.filter {
            $0.normalizedValue != preferred.normalizedValue
        }
        return result
    }

    public static func fallback(handle: ContactHandle, handleRowID: Int64? = nil, resolvedAt: Date = Date()) -> Contact {
        let idSeed = handleRowID.map { "handle:\($0)" } ?? "handle:\(handle.normalizedValue)"
        let displayName = handle.value.isEmpty ? handle.normalizedValue : handle.value

        return Contact(
            id: ContactID(rawValue: idSeed),
            displayName: displayName,
            handles: [handle],
            avatar: ContactAvatar(
                initials: ContactInitials.initials(for: displayName),
                colorSeed: handle.normalizedValue
            ),
            lastResolvedAt: resolvedAt
        )
    }
}

enum ContactInitials {
    static func initials(for name: String) -> String {
        let words = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" || $0 == "." })
            .map(String.init)

        let letters = words
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        if !letters.isEmpty {
            return letters
        }

        return String(name.prefix(1)).uppercased()
    }
}

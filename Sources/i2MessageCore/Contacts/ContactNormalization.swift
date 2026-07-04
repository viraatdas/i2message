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

        guard trimmed.hasPrefix("+") else {
            return digits
        }

        return "+" + digits
    }
}

extension Contact {
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

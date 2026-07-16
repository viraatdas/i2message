import XCTest
@testable import i2MessageCore

final class ContactNormalizationTests: XCTestCase {
    func testE164AndLocallyFormattedNumbersNormalizeToSameKey() {
        // The exact symptom behind "numbers instead of names": chat.db stores
        // E.164 handles while Contacts often stores the same number without a
        // country code. Both must collapse to the same normalized key.
        let fromChatDB = ContactHandleNormalizer.normalizedValue("+15551234567", kind: .phoneNumber)
        let fromContacts = ContactHandleNormalizer.normalizedValue("(555) 123-4567", kind: .phoneNumber)
        XCTAssertEqual(fromChatDB, fromContacts)
        XCTAssertEqual(fromChatDB, "5551234567")
    }

    func testSpacedAndDashedVariantsMatch() {
        let a = ContactHandleNormalizer.normalizedValue("555-123-4567", kind: .phoneNumber)
        let b = ContactHandleNormalizer.normalizedValue("555 123 4567", kind: .phoneNumber)
        let c = ContactHandleNormalizer.normalizedValue("1 (555) 123-4567", kind: .phoneNumber)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
    }

    func testShortNumbersArePreservedVerbatim() {
        // Shortcodes and other sub-10-digit numbers keep all their digits.
        XCTAssertEqual(ContactHandleNormalizer.normalizedValue("24466", kind: .phoneNumber), "24466")
    }

    func testEmailsLowercaseAndAreUntouchedByPhoneLogic() {
        XCTAssertEqual(
            ContactHandleNormalizer.normalizedValue("User@Example.com", kind: .emailAddress),
            "user@example.com"
        )
    }

    func testInferredKindMatchesExplicitKind() {
        // handleKind inference should route a formatted phone number through the
        // phone path even when the caller doesn't pass an explicit kind.
        let inferred = ContactHandleNormalizer.contactHandle(value: "(555) 123-4567")
        XCTAssertEqual(inferred.kind, .phoneNumber)
        XCTAssertEqual(inferred.normalizedValue, "5551234567")
    }

    func testResolvedContactPrioritizesExactChatHandleAndService() {
        let contact = Contact(
            id: "contact.multi",
            displayName: "Multi Number",
            handles: [
                ContactHandleNormalizer.contactHandle(value: "+1 415 555 0100", service: .unknown),
                ContactHandleNormalizer.contactHandle(value: "+1 415 555 0200", service: .unknown)
            ]
        )

        let prioritized = contact.prioritizing(
            messageHandle: MessageHandle(value: "+1 (415) 555-0200", service: .sms)
        )

        XCTAssertEqual(prioritized.handles.first?.value, "+1 (415) 555-0200")
        XCTAssertEqual(prioritized.handles.first?.service, .sms)
        XCTAssertEqual(prioritized.handles.dropFirst().first?.normalizedValue, "4155550100")
    }
}

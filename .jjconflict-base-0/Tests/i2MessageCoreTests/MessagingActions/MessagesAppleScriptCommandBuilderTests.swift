import XCTest
@testable import i2MessageCore

final class MessagesAppleScriptCommandBuilderTests: XCTestCase {
    func testSendCommandEscapesDraftTextAndRedactsDescription() throws {
        let draft = MessageDraft(
            target: .handles([Self.handle(value: "maya@example.com", kind: .emailAddress)]),
            text: "Hello \"Maya\"\nBackslash \\ ok",
            requestedService: .iMessage
        )

        let command = try MessagesAppleScriptCommandBuilder.sendCommand(for: draft)

        XCTAssertTrue(command.source.contains("set targetBuddy to buddy \"maya@example.com\" of targetService"))
        XCTAssertTrue(command.source.contains("send \"Hello \\\"Maya\\\"\\nBackslash \\\\ ok\" to targetBuddy"))
        XCTAssertFalse(command.redactedDescription.contains("maya@example.com"))
        XCTAssertFalse(command.redactedDescription.contains("Hello"))
    }

    func testAttachmentCommandUsesPOSIXFileWithoutMutatingMessagesStorage() throws {
        let draft = MessageDraft(
            target: .handles([Self.handle()]),
            text: "",
            attachments: [
                DraftAttachment(
                    id: "attachment.test",
                    fileURL: URL(fileURLWithPath: "/tmp/Invoice.pdf"),
                    filename: "Invoice.pdf",
                    uniformTypeIdentifier: "com.adobe.pdf"
                )
            ],
            requestedService: .iMessage
        )

        let command = try MessagesAppleScriptCommandBuilder.sendCommand(for: draft)

        XCTAssertTrue(command.source.contains("send POSIX file \"/tmp/Invoice.pdf\" to targetBuddy"))
        XCTAssertFalse(command.source.localizedCaseInsensitiveContains("chat.db"))
    }

    func testSMSDirectSendIsUnavailableByDefault() {
        let draft = MessageDraft(
            target: .handles([Self.handle(service: .sms)]),
            text: "Carrier path",
            requestedService: .sms
        )

        XCTAssertThrowsError(try MessagesAppleScriptCommandBuilder.sendCommand(for: draft)) { error in
            guard case MessagingActionError.serviceUnavailable(let requested, _, let fallback) = error else {
                return XCTFail("Expected serviceUnavailable, got \(error)")
            }

            XCTAssertEqual(requested, .sms)
            XCTAssertTrue(fallback.contains("Messages.app"))
        }
    }

    func testExistingConversationIDIsNotTreatedAsAutomationAddress() {
        let draft = MessageDraft(
            target: .existingConversation("conversation.private-id"),
            text: "Do not address chat.db IDs",
            requestedService: .iMessage
        )

        XCTAssertThrowsError(try MessagesAppleScriptCommandBuilder.sendCommand(for: draft)) { error in
            guard case MessagingActionError.unsupportedCapability(let kind, let reason, _) = error else {
                return XCTFail("Expected unsupportedCapability, got \(error)")
            }

            XCTAssertEqual(kind, .sendMessage)
            XCTAssertTrue(reason.contains("read-only conversation identifier"))
        }
    }

    func testReplyCommandIsRejectedBecauseAppleScriptCannotAnchorReplies() {
        let draft = MessageDraft(
            target: .handles([Self.handle()]),
            text: "Anchored reply",
            replyToMessageID: "message.anchor",
            requestedService: .iMessage
        )

        XCTAssertThrowsError(try MessagesAppleScriptCommandBuilder.sendCommand(for: draft)) { error in
            guard case MessagingActionError.unsupportedCapability(let kind, let reason, _) = error else {
                return XCTFail("Expected unsupportedCapability, got \(error)")
            }

            XCTAssertEqual(kind, .replyToMessage)
            XCTAssertTrue(reason.contains("specific prior bubble"))
        }
    }

    private static func handle(
        value: String = "+1 (415) 555-0134",
        kind: ContactHandleKind = .phoneNumber,
        service: MessageService = .iMessage
    ) -> ContactHandle {
        ContactHandle(
            value: value,
            normalizedValue: value.replacingOccurrences(of: " ", with: ""),
            kind: kind,
            service: service
        )
    }
}

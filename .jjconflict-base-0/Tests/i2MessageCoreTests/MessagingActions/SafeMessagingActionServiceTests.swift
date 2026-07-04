import XCTest
@testable import i2MessageCore

final class SafeMessagingActionServiceTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSinceReferenceDate: 810_000_000)

    func testValidateReturnsAwaitingPermissionBeforeAppleEventsGrant() async throws {
        let automation = FakeAutomation()
        let service = makeService(
            permissionState: .notDetermined,
            automation: automation
        )

        let operation = try await service.validate(Self.iMessageDraft())
        let executedCount = await automation.executedCount()

        XCTAssertEqual(operation.state, .awaitingPermission)
        XCTAssertEqual(executedCount, 0)
    }

    func testSendDoesNotExecuteAutomationUntilPermissionIsGranted() async throws {
        let automation = FakeAutomation()
        let service = makeService(
            permissionState: .notDetermined,
            automation: automation
        )

        do {
            _ = try await service.send(Self.iMessageDraft())
            XCTFail("Expected send to require Automation permission")
        } catch let error as MessagingActionError {
            guard case .permissionRequired(let permission, _) = error else {
                return XCTFail("Expected permissionRequired, got \(error)")
            }
            XCTAssertEqual(permission, .appleEventsMessages)
        }

        let executedCount = await automation.executedCount()
        XCTAssertEqual(executedCount, 0)
    }

    func testGrantedSendExecutesAutomationAndReturnsReceiptWithoutPrivateMessageID() async throws {
        let automation = FakeAutomation()
        let service = makeService(
            permissionState: .granted,
            automation: automation
        )

        let receipt = try await service.send(Self.iMessageDraft())

        XCTAssertEqual(receipt.operationID, "operation.test")
        XCTAssertNil(receipt.messageID)
        XCTAssertEqual(receipt.sentAt, fixedDate)
        let executedCount = await automation.executedCount()
        XCTAssertEqual(executedCount, 1)
    }

    func testAttachmentSizeIsValidatedBeforeAutomation() async throws {
        let automation = FakeAutomation()
        let attachmentURL = URL(fileURLWithPath: "/tmp/Huge.mov")
        let inspector = FakeAttachmentInspector(
            readableURLs: [attachmentURL],
            byteCounts: [attachmentURL: 2_000]
        )
        let service = makeService(
            permissionState: .granted,
            automation: automation,
            attachmentInspector: inspector,
            policy: MessagingActionPolicy(maxAttachmentByteCount: 1_000)
        )
        let draft = MessageDraft(
            target: .handles([Self.handle()]),
            text: "",
            attachments: [
                DraftAttachment(
                    id: "attachment.huge",
                    fileURL: attachmentURL,
                    filename: "Huge.mov"
                )
            ],
            requestedService: .iMessage
        )

        do {
            _ = try await service.send(draft)
            XCTFail("Expected attachmentTooLarge")
        } catch let error as MessagingActionError {
            guard case .attachmentTooLarge(let filename, let byteCount, let maxByteCount) = error else {
                return XCTFail("Expected attachmentTooLarge, got \(error)")
            }
            XCTAssertEqual(filename, "Huge.mov")
            XCTAssertEqual(byteCount, 2_000)
            XCTAssertEqual(maxByteCount, 1_000)
        }

        let executedCount = await automation.executedCount()
        XCTAssertEqual(executedCount, 0)
    }

    func testAvailabilitySnapshotKeepsUnsupportedAndFallbackStatesExplicit() async {
        let service = makeService(permissionState: .denied)

        let snapshot = await service.availabilitySnapshot()

        XCTAssertEqual(snapshot.status(for: .sendMessage)?.state, .unavailable)
        XCTAssertEqual(snapshot.status(for: .pasteHandoff)?.state, .available)
        XCTAssertEqual(snapshot.status(for: .markRead)?.state, .unsupported)
        XCTAssertNotNil(snapshot.status(for: .openInMessages)?.fallback)
    }

    func testOpenConversationUsesHandoffInsteadOfPrivateMutation() async throws {
        let handoff = FakeHandoff()
        let service = makeService(
            permissionState: .denied,
            handoff: handoff
        )

        let result = try await service.openConversation(
            ConversationHandoffRequest(
                conversationID: "conversation.test",
                displayTitle: "Design review",
                handles: [Self.handle()],
                draftText: "Manual send"
            )
        )

        XCTAssertEqual(result.kind, .openInMessages)
        XCTAssertEqual(result.outcome, .handedOff)
        let openConversationCount = await handoff.openConversationCount()
        XCTAssertEqual(openConversationCount, 1)
    }

    func testMarkReadIsExplicitlyUnsupported() async {
        let service = makeService(permissionState: .granted)

        do {
            _ = try await service.markRead(MarkReadRequest(conversationID: "conversation.test"))
            XCTFail("Expected markRead to be unsupported")
        } catch let error as MessagingActionError {
            guard case .unsupportedCapability(let kind, let reason, _) = error else {
                return XCTFail("Expected unsupportedCapability, got \(error)")
            }
            XCTAssertEqual(kind, .markRead)
            XCTAssertTrue(reason.contains("No supported Messages.app automation API"))
        } catch {
            XCTFail("Expected MessagingActionError, got \(error)")
        }
    }

    private func makeService(
        permissionState: PermissionState,
        automation: FakeAutomation = FakeAutomation(),
        handoff: FakeHandoff = FakeHandoff(),
        attachmentInspector: any DraftAttachmentInspecting = FakeAttachmentInspector(),
        policy: MessagingActionPolicy = MessagingActionPolicy()
    ) -> SafeMessagingActionService {
        let fixedDate = self.fixedDate
        let permissionManager = FakePermissionManager(
            snapshot: PermissionSnapshot(
                statuses: [
                    PermissionStatus(
                        permission: .appleEventsMessages,
                        state: permissionState,
                        lastCheckedAt: fixedDate
                    ),
                    PermissionStatus(
                        permission: .contacts,
                        state: .notDetermined,
                        lastCheckedAt: fixedDate
                    ),
                    PermissionStatus(
                        permission: .notifications,
                        state: .notDetermined,
                        lastCheckedAt: fixedDate
                    )
                ]
            )
        )

        return SafeMessagingActionService(
            automation: automation,
            handoff: handoff,
            permissionManager: permissionManager,
            attachmentInspector: attachmentInspector,
            policy: policy,
            dateProvider: { fixedDate },
            idProvider: { "operation.test" }
        )
    }

    private static func iMessageDraft() -> MessageDraft {
        MessageDraft(
            target: .handles([handle()]),
            text: "Ready",
            requestedService: .iMessage
        )
    }

    private static func handle() -> ContactHandle {
        ContactHandle(
            value: "+1 (415) 555-0134",
            normalizedValue: "+14155550134",
            kind: .phoneNumber,
            service: .iMessage
        )
    }
}

private actor FakeAutomation: MessagesAutomationControlling {
    private var commands: [MessagesAppleScriptCommand] = []
    private let available: Bool
    private let failure: MessagesAutomationFailure?

    init(
        available: Bool = true,
        failure: MessagesAutomationFailure? = nil
    ) {
        self.available = available
        self.failure = failure
    }

    func isMessagesAvailable() async -> Bool {
        available
    }

    func execute(_ command: MessagesAppleScriptCommand) async throws -> MessagesAutomationResult {
        commands.append(command)
        if let failure {
            throw failure
        }
        return MessagesAutomationResult()
    }

    func openMessages() async throws {}

    func executedCount() -> Int {
        commands.count
    }
}

private actor FakeHandoff: MessagesHandoffControlling {
    private var openConversationRequests: [ConversationHandoffRequest] = []
    private var contactRequests: [ContactHandoffRequest] = []
    private var pasteRequests: [PasteHandoffRequest] = []

    func openMessages(with request: ConversationHandoffRequest) async throws {
        openConversationRequests.append(request)
    }

    func openContact(with request: ContactHandoffRequest) async throws {
        contactRequests.append(request)
    }

    func copyToPasteboard(_ request: PasteHandoffRequest) async throws {
        pasteRequests.append(request)
    }

    func dragItems(for request: DragHandoffRequest) async throws -> [MessagingHandoffItem] {
        request.attachments.map { attachment in
            MessagingHandoffItem(
                id: attachment.id.rawValue,
                kind: .fileURL,
                displayName: attachment.filename,
                value: attachment.fileURL.absoluteString
            )
        }
    }

    func openConversationCount() -> Int {
        openConversationRequests.count
    }
}

private actor FakePermissionManager: PermissionManaging {
    private var snapshot: PermissionSnapshot

    init(snapshot: PermissionSnapshot) {
        self.snapshot = snapshot
    }

    func permissionSnapshot() async -> PermissionSnapshot {
        snapshot
    }

    func request(_ permission: AppPermission) async throws -> PermissionStatus {
        snapshot.status(for: permission) ?? PermissionStatus(
            permission: permission,
            state: .notDetermined,
            lastCheckedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    func openSystemSettings(for permission: AppPermission) async {}
}

private struct FakeAttachmentInspector: DraftAttachmentInspecting {
    var readableURLs: Set<URL> = []
    var byteCounts: [URL: Int64] = [:]

    func fileExists(at fileURL: URL) async -> Bool {
        readableURLs.isEmpty || readableURLs.contains(fileURL)
    }

    func byteCount(for fileURL: URL) async throws -> Int64? {
        byteCounts[fileURL]
    }
}

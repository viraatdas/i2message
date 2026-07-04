import Foundation

public enum MockData {
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 805_000_000)

    public static let currentUser = Contact(
        id: "contact.me",
        displayName: "You",
        handles: [
            ContactHandle(
                value: "you@example.com",
                normalizedValue: "you@example.com",
                kind: .emailAddress,
                service: .iMessage
            )
        ],
        avatar: ContactAvatar(initials: "ME", colorSeed: "amber"),
        isCurrentUser: true,
        lastResolvedAt: baseDate
    )

    public static let contacts: [Contact] = [
        currentUser,
        Contact(
            id: "contact.maya",
            displayName: "Maya Chen",
            handles: [
                ContactHandle(
                    value: "+1 (415) 555-0134",
                    normalizedValue: "+14155550134",
                    kind: .phoneNumber,
                    service: .iMessage
                )
            ],
            avatar: ContactAvatar(initials: "MC", colorSeed: "plum"),
            lastResolvedAt: baseDate
        ),
        Contact(
            id: "contact.eli",
            displayName: "Eli Parker",
            handles: [
                ContactHandle(
                    value: "eli@example.com",
                    normalizedValue: "eli@example.com",
                    kind: .emailAddress,
                    service: .iMessage
                )
            ],
            avatar: ContactAvatar(initials: "EP", colorSeed: "blue"),
            lastResolvedAt: baseDate
        ),
        Contact(
            id: "contact.ava",
            displayName: "Ava Patel",
            handles: [
                ContactHandle(
                    value: "+1 (650) 555-0188",
                    normalizedValue: "+16505550188",
                    kind: .phoneNumber,
                    service: .sms
                )
            ],
            avatar: ContactAvatar(initials: "AP", colorSeed: "green"),
            lastResolvedAt: baseDate
        )
    ]

    public static let conversations: [Conversation] = [
        Conversation(
            id: "conversation.design-review",
            title: "Design review",
            participants: [contacts[1], currentUser],
            kind: .direct,
            service: .iMessage,
            unreadCount: 2,
            pinnedRank: 0,
            lastMessage: LastMessagePreview(
                messageID: "message.design.4",
                senderID: contacts[1].id,
                text: "The transcript feels much faster with paged loading.",
                sentAt: date(minutesAgo: 5),
                hasAttachments: false
            ),
            updatedAt: date(minutesAgo: 5)
        ),
        Conversation(
            id: "conversation.weekend",
            title: "Weekend plans",
            participants: [contacts[2], contacts[3], currentUser],
            kind: .group,
            service: .iMessage,
            unreadCount: 0,
            lastMessage: LastMessagePreview(
                messageID: "message.weekend.3",
                senderID: currentUser.id,
                text: "I can bring coffee and the adapter.",
                sentAt: date(minutesAgo: 44),
                hasAttachments: false
            ),
            updatedAt: date(minutesAgo: 44),
            lastReadMessageID: "message.weekend.3"
        ),
        Conversation(
            id: "conversation.receipts",
            title: "Receipts",
            participants: [contacts[3], currentUser],
            kind: .direct,
            service: .sms,
            unreadCount: 0,
            isMuted: true,
            lastMessage: LastMessagePreview(
                messageID: "message.receipts.2",
                senderID: contacts[3].id,
                text: "Sent the PDF from last week.",
                sentAt: date(hoursAgo: 3),
                hasAttachments: true
            ),
            updatedAt: date(hoursAgo: 3),
            lastReadMessageID: "message.receipts.2"
        )
    ]

    public static let messagesByConversation: [ConversationID: [Message]] = [
        "conversation.design-review": [
            Message(
                id: "message.design.1",
                conversationID: "conversation.design-review",
                senderID: contacts[1].id,
                body: .text("Can you look at the search flow before lunch?"),
                direction: .incoming,
                service: .iMessage,
                status: .delivered,
                sentAt: date(minutesAgo: 38),
                receivedAt: date(minutesAgo: 38)
            ),
            Message(
                id: "message.design.2",
                conversationID: "conversation.design-review",
                senderID: currentUser.id,
                body: .text("Yes. I am checking exact search, semantic snippets, and keyboard navigation together."),
                direction: .outgoing,
                service: .iMessage,
                status: .read,
                sentAt: date(minutesAgo: 31)
            ),
            Message(
                id: "message.design.3",
                conversationID: "conversation.design-review",
                senderID: currentUser.id,
                body: .text("The important part is that long histories paginate without losing scroll position."),
                direction: .outgoing,
                service: .iMessage,
                status: .delivered,
                sentAt: date(minutesAgo: 18)
            ),
            Message(
                id: "message.design.4",
                conversationID: "conversation.design-review",
                senderID: contacts[1].id,
                body: .text("The transcript feels much faster with paged loading."),
                direction: .incoming,
                service: .iMessage,
                status: .delivered,
                sentAt: date(minutesAgo: 5),
                receivedAt: date(minutesAgo: 5)
            )
        ],
        "conversation.weekend": [
            Message(
                id: "message.weekend.1",
                conversationID: "conversation.weekend",
                senderID: contacts[2].id,
                body: .text("Saturday still works? I can be there around 10."),
                direction: .incoming,
                service: .iMessage,
                status: .read,
                sentAt: date(hoursAgo: 2),
                receivedAt: date(hoursAgo: 2)
            ),
            Message(
                id: "message.weekend.2",
                conversationID: "conversation.weekend",
                senderID: contacts[3].id,
                body: .text("Works for me. I will bring the printouts."),
                direction: .incoming,
                service: .iMessage,
                status: .read,
                sentAt: date(minutesAgo: 71),
                receivedAt: date(minutesAgo: 71)
            ),
            Message(
                id: "message.weekend.3",
                conversationID: "conversation.weekend",
                senderID: currentUser.id,
                body: .text("I can bring coffee and the adapter."),
                direction: .outgoing,
                service: .iMessage,
                status: .delivered,
                sentAt: date(minutesAgo: 44)
            )
        ],
        "conversation.receipts": [
            Message(
                id: "message.receipts.1",
                conversationID: "conversation.receipts",
                senderID: currentUser.id,
                body: .text("Do you still have the invoice from last week?"),
                direction: .outgoing,
                service: .sms,
                status: .sent,
                sentAt: date(hoursAgo: 4)
            ),
            Message(
                id: "message.receipts.2",
                conversationID: "conversation.receipts",
                senderID: contacts[3].id,
                body: .text("Sent the PDF from last week."),
                direction: .incoming,
                service: .sms,
                status: .delivered,
                sentAt: date(hoursAgo: 3),
                receivedAt: date(hoursAgo: 3),
                attachments: [
                    MessageAttachment(
                        id: "attachment.receipt.pdf",
                        messageID: "message.receipts.2",
                        kind: .file,
                        filename: "Invoice-Last-Week.pdf",
                        uniformTypeIdentifier: "com.adobe.pdf",
                        byteCount: 241_920
                    )
                ]
            )
        ]
    ]

    public static var allMessages: [Message] {
        messagesByConversation.values.flatMap { $0 }.sorted { $0.sentAt < $1.sentAt }
    }

    public static func messages(for conversationID: ConversationID) -> [Message] {
        messagesByConversation[conversationID, default: []]
    }

    private static func date(minutesAgo: TimeInterval) -> Date {
        baseDate.addingTimeInterval(-minutesAgo * 60)
    }

    private static func date(hoursAgo: TimeInterval) -> Date {
        baseDate.addingTimeInterval(-hoursAgo * 60 * 60)
    }
}

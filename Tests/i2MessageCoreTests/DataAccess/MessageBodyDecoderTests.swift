import XCTest
@testable import i2MessageCore

final class MessageBodyDecoderTests: XCTestCase {
    func testPrefersPlainTextColumn() {
        XCTAssertEqual(
            MessageBodyDecoder.bestText(text: "hello", attributedBody: typedstreamBlob(for: "ignored")),
            "hello"
        )
    }

    func testDecodesShortAttributedBody() {
        XCTAssertEqual(
            MessageBodyDecoder.bestText(text: nil, attributedBody: typedstreamBlob(for: "hey, are we still on?")),
            "hey, are we still on?"
        )
    }

    func testDecodesLongAttributedBodyWithTwoByteLength() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(
            MessageBodyDecoder.bestText(text: "", attributedBody: typedstreamBlob(for: long)),
            long
        )
    }

    func testStripsAttachmentPlaceholders() {
        XCTAssertEqual(
            MessageBodyDecoder.bestText(text: nil, attributedBody: typedstreamBlob(for: "\u{FFFC}see photo")),
            "see photo"
        )
    }

    func testMalformedBlobReturnsNil() {
        XCTAssertNil(MessageBodyDecoder.plainText(fromAttributedBody: Data([0x01, 0x02, 0x03])))
        XCTAssertNil(MessageBodyDecoder.plainText(fromAttributedBody: Data()))

        // Truncated stream: declares more bytes than it has.
        var truncated = Data("streamtyped___NSString".utf8)
        truncated.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05, 0xFF])
        XCTAssertNil(MessageBodyDecoder.plainText(fromAttributedBody: truncated))
    }

    func testEditHistoryDecodesCraftedSummaryInfo() throws {
        let plist: [String: Any] = [
            "ec": [
                "0": [
                    ["d": 700_000_000.0, "t": typedstreamBlob(for: "first draft")],
                    ["d": 700_000_100.0, "t": typedstreamBlob(for: "final wording")],
                ]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let versions = MessageBodyDecoder.editHistory(fromSummaryInfo: data)

        XCTAssertEqual(versions.map(\.text), ["first draft", "final wording"])
        XCTAssertLessThan(versions[0].editedAt, versions[1].editedAt)
    }

    func testEditHistoryDecodesRealChatDBSummaryInfo() throws {
        // Captured verbatim from a macOS 26.3 chat.db `message_summary_info`
        // for a once-edited message (two versions in the "ec" chain).
        let data = try XCTUnwrap(Data(base64Encoded: Self.realSummaryInfoBase64))

        let versions = MessageBodyDecoder.editHistory(fromSummaryInfo: data)

        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(
            versions.first?.text,
            "you can just let it know Libra is a vendor and i completely trust them. we have verified and audited them"
        )
        XCTAssertTrue(versions[1].text.hasSuffix("there is nothing to worry about here."))
        XCTAssertLessThan(versions[0].editedAt, versions[1].editedAt)
    }

    func testEditHistoryToleratesMissingOrMalformedSummaryInfo() {
        XCTAssertEqual(MessageBodyDecoder.editHistory(fromSummaryInfo: nil), [])
        XCTAssertEqual(MessageBodyDecoder.editHistory(fromSummaryInfo: Data()), [])
        XCTAssertEqual(MessageBodyDecoder.editHistory(fromSummaryInfo: Data([0x00, 0x01, 0x02])), [])
    }

    /// Builds the minimal byte layout the decoder walks: preamble, "NSString"
    /// class name, 5 bookkeeping bytes, then a length-prefixed UTF-8 payload.
    private func typedstreamBlob(for text: String) -> Data {
        var data = Data("\u{04}\u{0B}streamtyped___NSMutableAttributedString___NSAttributedString___NSString".utf8)
        data.append(contentsOf: [0x01, 0x94, 0x84, 0x01, 0x2B])

        let utf8 = Array(text.utf8)
        if utf8.count < 0x81 {
            data.append(UInt8(utf8.count))
        } else if utf8.count <= UInt16.max {
            data.append(0x81)
            data.append(UInt8(utf8.count & 0xFF))
            data.append(UInt8((utf8.count >> 8) & 0xFF))
        } else {
            data.append(0x82)
            data.append(UInt8(utf8.count & 0xFF))
            data.append(UInt8((utf8.count >> 8) & 0xFF))
            data.append(UInt8((utf8.count >> 16) & 0xFF))
            data.append(UInt8((utf8.count >> 24) & 0xFF))
        }
        data.append(contentsOf: utf8)
        data.append(contentsOf: [0x86, 0x84])
        return data
    }

    private static let realSummaryInfoBase64 = """
        YnBsaXN0MDDWAQIDBAUGBwgTFBYXU2VuY1JlY1N1c3RSZXBVZW9nY2RTb3RyCNEJClEwogsQ0gwNDg9RdFFkTxEBGAQLc3RyZWFtdHlwZW\
        SB6AOEAUCEhIQSTlNBdHRyaWJ1dGVkU3RyaW5nAISECE5TT2JqZWN0AIWShISECE5TU3RyaW5nAZSEAStpeW91IGNhbiBqdXN0IGxldCBp\
        dCBrbm93IExpYnJhIGlzIGEgdmVuZG9yIGFuZCBpIGNvbXBsZXRlbHkgdHJ1c3QgdGhlbS4gd2UgaGF2ZSB2ZXJpZmllZCBhbmQgYXVkaX\
        RlZCB0aGVthoQCaUkBaZKEhIQMTlNEaWN0aW9uYXJ5AJSEAWkBkoSWlh1fX2tJTU1lc3NhZ2VQYXJ0QXR0cmlidXRlTmFtZYaShISECE5T\
        TnVtYmVyAISEB05TVmFsdWUAlIQBKoSZmQCGhoYjQcf+25ySsCDSDA0REk8RAV8EC3N0cmVhbXR5cGVkgegDhAFAhISEEk5TQXR0cmlidX\
        RlZFN0cmluZwCEhAhOU09iamVjdACFkoSEhAhOU1N0cmluZwGUhAErgawAeW91IGNhbiBqdXN0IGxldCBpdCBrbm93IExpYnJhIGlzIGEg\
        dmVuZG9yIGFuZCBpIGNvbXBsZXRlbHkgdHJ1c3QgdGhlbS4gd2UgaGF2ZSB2ZXJpZmllZCBhbmQgYXVkaXRlZCB0aGVtLiBwbGVhc2UgZ2\
        8gYWhlYWQgYW5kIGRvIGl0LiB0aGVyZSBpcyBub3RoaW5nIHRvIHdvcnJ5IGFib3V0IGhlcmUuIIaEAmlJAYGsAJKEhIQMTlNEaWN0aW9u\
        YXJ5AJSEAWkBkoSWlh1fX2tJTU1lc3NhZ2VQYXJ0QXR0cmlidXRlTmFtZYaShISECE5TTnVtYmVyAISEB05TVmFsdWUAlIQBKoSZmQCGho\
        YjQcf+26KuQ7MJoRUQABAB0QkY0hkaFRtSbG9SbGUQaQAIABUAGQAcACAAIwApAC0ALgAxADMANgA7AD0APwFbAWQBaQLMAtUC1gLYAtoC\
        3ALfAuQC5wLqAAAAAAAAAgEAAAAAAAAAHAAAAAAAAAAAAAAAAAAAAuw=
        """
}

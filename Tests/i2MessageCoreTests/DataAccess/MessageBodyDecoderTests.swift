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
}

import XCTest
@testable import i2Message
import i2MessageCore

final class ThreadSwipeGestureStateTests: XCTestCase {
    func testHorizontalSwipeOpensOnlyOnceUntilGestureEnds() {
        let messageID = MessageID(rawValue: "message.thread-root")
        var state = ThreadSwipeGestureState()
        state.setHoveredMessageID(messageID)

        let intent = state.handleScroll(deltaX: 20, deltaY: 1, phase: .changed)
        XCTAssertTrue(intent.shouldConsumeEvent)
        XCTAssertNil(intent.openedMessageID)
        XCTAssertGreaterThan(abs(state.visualOffset), 0)

        let opened = state.handleScroll(deltaX: 75, deltaY: 0, phase: .changed)
        XCTAssertTrue(opened.shouldConsumeEvent)
        XCTAssertEqual(opened.openedMessageID, messageID)
        XCTAssertEqual(state.visualOffset, 0, accuracy: 0.001)

        let repeated = state.handleScroll(deltaX: 110, deltaY: 0, phase: .changed)
        XCTAssertTrue(repeated.shouldConsumeEvent)
        XCTAssertNil(repeated.openedMessageID)

        let ended = state.handleScroll(deltaX: 0, deltaY: 0, phase: .ended)
        XCTAssertFalse(ended.shouldConsumeEvent)

        XCTAssertNil(state.handleScroll(deltaX: 20, deltaY: 0, phase: .changed).openedMessageID)
        XCTAssertEqual(
            state.handleScroll(deltaX: 70, deltaY: 0, phase: .changed).openedMessageID,
            messageID
        )
    }

    func testVerticalScrollPassesThroughWithoutOpeningThread() {
        let messageID = MessageID(rawValue: "message.vertical")
        var state = ThreadSwipeGestureState()
        state.setHoveredMessageID(messageID)

        let vertical = state.handleScroll(deltaX: 4, deltaY: 32, phase: .changed)
        XCTAssertFalse(vertical.shouldConsumeEvent)
        XCTAssertNil(vertical.openedMessageID)
        XCTAssertEqual(state.visualOffset, 0, accuracy: 0.001)

        let continuedVertical = state.handleScroll(deltaX: 80, deltaY: 120, phase: .changed)
        XCTAssertFalse(continuedVertical.shouldConsumeEvent)
        XCTAssertNil(continuedVertical.openedMessageID)
    }

    func testMomentumPassesThroughAndClearsPartialSwipe() {
        let messageID = MessageID(rawValue: "message.momentum")
        var state = ThreadSwipeGestureState()
        state.setHoveredMessageID(messageID)

        XCTAssertTrue(state.handleScroll(deltaX: 24, deltaY: 0, phase: .changed).shouldConsumeEvent)
        XCTAssertGreaterThan(abs(state.visualOffset), 0)

        let momentum = state.handleScroll(deltaX: 120, deltaY: 0, phase: .momentum)
        XCTAssertFalse(momentum.shouldConsumeEvent)
        XCTAssertNil(momentum.openedMessageID)
        XCTAssertTrue(momentum.didReset)
        XCTAssertEqual(state.visualOffset, 0, accuracy: 0.001)
    }

    func testChangingHoveredMessageResetsPartialSwipe() {
        let first = MessageID(rawValue: "message.first")
        let second = MessageID(rawValue: "message.second")
        var state = ThreadSwipeGestureState()
        state.setHoveredMessageID(first)

        XCTAssertTrue(state.handleScroll(deltaX: 24, deltaY: 0, phase: .changed).shouldConsumeEvent)
        XCTAssertGreaterThan(abs(state.visualOffset), 0)

        state.setHoveredMessageID(second)
        XCTAssertEqual(state.visualOffset, 0, accuracy: 0.001)
        XCTAssertEqual(
            state.handleScroll(deltaX: 95, deltaY: 0, phase: .changed).openedMessageID,
            second
        )
    }
}

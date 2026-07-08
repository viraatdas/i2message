import CoreGraphics
import i2MessageCore

/// Small state machine for trackpad horizontal-swipe-to-thread. It separates
/// horizontal intent from ordinary transcript scrolling so vertical deltas and
/// momentum keep flowing to the ScrollView.
struct ThreadSwipeGestureState: Equatable {
    enum ScrollPhase: Equatable {
        case changed
        case ended
        case cancelled
        case momentum
    }

    struct Configuration: Equatable {
        var intentDistance: CGFloat = 12
        var activationDistance: CGFloat = 90
        var horizontalDominance: CGFloat = 1.35
        var verticalIntentDistance: CGFloat = 8
        var verticalDominance: CGFloat = 1.05
        var visualScale: CGFloat = 0.45
        var maxVisualOffset: CGFloat = 44
    }

    struct Update: Equatable {
        var shouldConsumeEvent: Bool
        var openedMessageID: MessageID?
        var didReset: Bool

        static let passThrough = Update(
            shouldConsumeEvent: false,
            openedMessageID: nil,
            didReset: false
        )
    }

    private enum Axis: Equatable {
        case horizontal
        case vertical
    }

    var configuration = Configuration()
    private(set) var hoveredMessageID: MessageID?
    private(set) var translationX: CGFloat = 0
    private var translationY: CGFloat = 0
    private var lockedAxis: Axis?
    private var openedDuringCurrentGesture = false

    var isTracking: Bool {
        hoveredMessageID != nil
            && (translationX != 0 || translationY != 0 || lockedAxis != nil || openedDuringCurrentGesture)
    }

    var progress: CGFloat {
        guard lockedAxis == .horizontal, !openedDuringCurrentGesture else {
            return 0
        }
        return min(1, abs(translationX) / configuration.activationDistance)
    }

    var visualOffset: CGFloat {
        guard lockedAxis == .horizontal, !openedDuringCurrentGesture else {
            return 0
        }
        let offset = translationX * configuration.visualScale
        return max(-configuration.maxVisualOffset, min(configuration.maxVisualOffset, offset))
    }

    mutating func setHoveredMessageID(_ messageID: MessageID?) {
        guard hoveredMessageID != messageID else {
            return
        }
        hoveredMessageID = messageID
        resetTracking()
    }

    @discardableResult
    mutating func resetGesture() -> Bool {
        resetTracking()
    }

    mutating func handleScroll(deltaX: CGFloat, deltaY: CGFloat, phase: ScrollPhase) -> Update {
        guard let hoveredMessageID else {
            let didReset = resetTracking()
            return Update(shouldConsumeEvent: false, openedMessageID: nil, didReset: didReset)
        }

        switch phase {
        case .ended, .cancelled, .momentum:
            let didReset = resetTracking()
            return Update(shouldConsumeEvent: false, openedMessageID: nil, didReset: didReset)
        case .changed:
            break
        }

        guard deltaX != 0 || deltaY != 0 else {
            return .passThrough
        }

        if lockedAxis == .vertical {
            return .passThrough
        }

        if lockedAxis == .horizontal {
            return trackHorizontal(deltaX: deltaX, deltaY: deltaY, hoveredMessageID: hoveredMessageID)
        }

        translationX += deltaX
        translationY += deltaY

        let absX = abs(translationX)
        let absY = abs(translationY)

        if absY >= configuration.verticalIntentDistance,
           absY >= absX * configuration.verticalDominance {
            translationX = 0
            translationY = 0
            lockedAxis = .vertical
            openedDuringCurrentGesture = false
            return .passThrough
        }

        if absX >= configuration.intentDistance,
           absX >= max(configuration.intentDistance, absY * configuration.horizontalDominance) {
            lockedAxis = .horizontal
            return maybeOpenHoveredMessage(hoveredMessageID)
        }

        return .passThrough
    }

    private mutating func trackHorizontal(deltaX: CGFloat, deltaY: CGFloat, hoveredMessageID: MessageID) -> Update {
        if openedDuringCurrentGesture {
            return Update(shouldConsumeEvent: true, openedMessageID: nil, didReset: false)
        }

        translationX += deltaX
        translationY += deltaY
        return maybeOpenHoveredMessage(hoveredMessageID)
    }

    private mutating func maybeOpenHoveredMessage(_ hoveredMessageID: MessageID) -> Update {
        guard !openedDuringCurrentGesture else {
            return Update(shouldConsumeEvent: true, openedMessageID: nil, didReset: false)
        }

        if abs(translationX) >= configuration.activationDistance {
            openedDuringCurrentGesture = true
            translationX = 0
            translationY = 0
            return Update(shouldConsumeEvent: true, openedMessageID: hoveredMessageID, didReset: true)
        }

        return Update(shouldConsumeEvent: true, openedMessageID: nil, didReset: false)
    }

    @discardableResult
    private mutating func resetTracking() -> Bool {
        let didReset = translationX != 0 || translationY != 0 || lockedAxis != nil || openedDuringCurrentGesture
        translationX = 0
        translationY = 0
        lockedAxis = nil
        openedDuringCurrentGesture = false
        return didReset
    }
}

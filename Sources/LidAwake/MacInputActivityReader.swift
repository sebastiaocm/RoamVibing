import CoreGraphics
import Foundation
import LidAwakeCore

final class MacInputActivityReader: InputActivityReadingProviding {
    private let eventTypes: [CGEventType] = [
        .keyDown,
        .flagsChanged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel
    ]

    func secondsSinceLastKeyboardOrMouseInput() -> TimeInterval? {
        let idleTimes = eventTypes
            .map {
                CGEventSource.secondsSinceLastEventType(
                    .combinedSessionState,
                    eventType: $0
                )
            }
            .filter { $0.isFinite && $0 >= 0 }

        return idleTimes.min()
    }
}

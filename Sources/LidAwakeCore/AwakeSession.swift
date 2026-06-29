import Foundation

public enum SessionMode: Equatable {
    case normal
    case closedLid
}

public enum SessionState: Equatable {
    case stopped
    case running(SessionMode)
}

public enum ClosedLidPowerChangeIntent: Equatable {
    case userInitiated
    case safety
}

public protocol AssertionManaging: AnyObject {
    func acquire() throws
    func release()
}

public protocol ClosedLidPowerManaging: AnyObject {
    func setClosedLidBypassEnabled(_ enabled: Bool) throws
    func setClosedLidBypassEnabled(_ enabled: Bool, intent: ClosedLidPowerChangeIntent) throws
}

public extension ClosedLidPowerManaging {
    func setClosedLidBypassEnabled(_ enabled: Bool, intent: ClosedLidPowerChangeIntent) throws {
        try setClosedLidBypassEnabled(enabled)
    }
}

public final class AwakeSession {
    private let assertions: AssertionManaging
    private let closedLidPower: ClosedLidPowerManaging
    private let stateLock = NSLock()
    private var unsafeState: SessionState = .stopped

    public private(set) var state: SessionState {
        get {
            withStateLock {
                unsafeState
            }
        }
        set {
            withStateLock {
                unsafeState = newValue
            }
        }
    }

    public init(assertions: AssertionManaging, closedLidPower: ClosedLidPowerManaging) {
        self.assertions = assertions
        self.closedLidPower = closedLidPower
    }

    public func start(mode: SessionMode) throws {
        try withStateLock {
            if unsafeState != .stopped {
                try stopLocked()
            }

            do {
                try assertions.acquire()
                if mode == .closedLid {
                    try closedLidPower.setClosedLidBypassEnabled(true, intent: .userInitiated)
                }
                unsafeState = .running(mode)
            } catch {
                assertions.release()
                unsafeState = .stopped
                throw error
            }
        }
    }

    public func stop(intent: ClosedLidPowerChangeIntent = .userInitiated) throws {
        try withStateLock {
            try stopLocked(intent: intent)
        }
    }

    private func stopLocked(intent: ClosedLidPowerChangeIntent = .userInitiated) throws {
        let previousState = unsafeState
        if previousState == .running(.closedLid) {
            try closedLidPower.setClosedLidBypassEnabled(false, intent: intent)
        }

        assertions.release()
        unsafeState = .stopped
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }
        return try body()
    }
}

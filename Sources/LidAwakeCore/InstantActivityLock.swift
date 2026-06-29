import Foundation
import Darwin

public protocol InputActivityReadingProviding: AnyObject {
    func secondsSinceLastKeyboardOrMouseInput() -> TimeInterval?
}

public protocol ScreenLocking: AnyObject {
    func lockScreen() throws
}

public enum LidState: Equatable {
    case open
    case closed
    case unknown
}

public protocol LidStateProviding: AnyObject {
    func currentLidState() -> LidState
}

public struct InstantActivityLockPolicy: Equatable {
    public static let defaultIdleArmingDelay: TimeInterval = 5
    public static let defaultActivityDetectionWindow: TimeInterval = 1

    public let isEnabled: Bool
    public let idleArmingDelay: TimeInterval
    public let activityDetectionWindow: TimeInterval

    public init(
        isEnabled: Bool,
        idleArmingDelay: TimeInterval,
        activityDetectionWindow: TimeInterval = Self.defaultActivityDetectionWindow
    ) {
        self.isEnabled = isEnabled
        self.idleArmingDelay = max(idleArmingDelay, 1)
        self.activityDetectionWindow = min(max(activityDetectionWindow, 0.1), 5)
    }
}

public enum InstantActivityLockResult: Equatable {
    case noAction
    case armed
    case locked
}

public final class InstantActivityLockGuard {
    private let session: AwakeSession
    private let inputActivityReader: InputActivityReadingProviding
    private let lidStateReader: LidStateProviding?
    private let screenLocker: ScreenLocking
    private var isArmed = false
    private var hasObservedClosedLid = false
    private var hasLockedDuringCurrentSession = false

    public var policy: InstantActivityLockPolicy

    public init(
        session: AwakeSession,
        inputActivityReader: InputActivityReadingProviding,
        lidStateReader: LidStateProviding? = nil,
        screenLocker: ScreenLocking,
        policy: InstantActivityLockPolicy
    ) {
        self.session = session
        self.inputActivityReader = inputActivityReader
        self.lidStateReader = lidStateReader
        self.screenLocker = screenLocker
        self.policy = policy
    }

    public func resetForSessionStart() {
        isArmed = false
        hasObservedClosedLid = false
        hasLockedDuringCurrentSession = false
    }

    public func reset() {
        isArmed = false
        hasObservedClosedLid = false
        hasLockedDuringCurrentSession = false
    }

    public func evaluate() throws -> InstantActivityLockResult {
        guard policy.isEnabled else {
            isArmed = false
            return .noAction
        }

        guard session.state != .stopped else {
            reset()
            return .noAction
        }

        guard !hasLockedDuringCurrentSession else {
            return .noAction
        }

        switch lidStateReader?.currentLidState() {
        case .closed:
            hasObservedClosedLid = true
        case .open where hasObservedClosedLid:
            return try lockAndDeactivateSession()
        case .open, .unknown, .none:
            break
        }

        guard let idleSeconds = inputActivityReader.secondsSinceLastKeyboardOrMouseInput() else {
            return .noAction
        }

        if isArmed, idleSeconds <= policy.activityDetectionWindow {
            return try lockAndDeactivateSession()
        }

        if idleSeconds >= policy.idleArmingDelay {
            isArmed = true
            return .armed
        }

        return .noAction
    }

    private func lockAndDeactivateSession() throws -> InstantActivityLockResult {
        try screenLocker.lockScreen()
        isArmed = false
        hasObservedClosedLid = false
        hasLockedDuringCurrentSession = true
        try session.stop(intent: .safety)
        return .locked
    }
}

public final class CommandScreenLocker: ScreenLocking {
    private let lockPerformer: LoginFrameworkScreenLockPerforming

    public init() {
        self.lockPerformer = LoginFrameworkScreenLockPerformer()
    }

    public func lockScreen() throws {
        try lockPerformer.lockScreen()
    }
}

private protocol LoginFrameworkScreenLockPerforming: AnyObject {
    func lockScreen() throws
}

private final class LoginFrameworkScreenLockPerformer: LoginFrameworkScreenLockPerforming {
    private typealias ImmediateLockFunction = @convention(c) () -> Void

    private let frameworkPath = "/System/Library/PrivateFrameworks/login.framework/login"
    private let symbolName = "SACLockScreenImmediate"

    func lockScreen() throws {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            throw ScreenLockError.lockFunctionUnavailable(reason: dynamicLoaderError())
        }

        guard let symbol = dlsym(handle, symbolName) else {
            let reason = dynamicLoaderError()
            dlclose(handle)
            throw ScreenLockError.lockFunctionUnavailable(reason: reason)
        }

        let lockScreen = unsafeBitCast(symbol, to: ImmediateLockFunction.self)
        lockScreen()
        dlclose(handle)
    }

    private func dynamicLoaderError() -> String {
        guard let error = dlerror() else {
            return "macOS did not provide more detail."
        }

        return String(cString: error)
    }
}

private enum ScreenLockError: LocalizedError {
    case lockFunctionUnavailable(reason: String)

    var errorDescription: String? {
        switch self {
        case let .lockFunctionUnavailable(reason):
            return """
            Could not lock the screen because the local macOS lock function is unavailable.

            \(reason)
            """
        }
    }
}

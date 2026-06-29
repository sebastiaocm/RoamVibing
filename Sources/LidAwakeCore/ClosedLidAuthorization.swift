import Foundation
import LocalAuthentication

public protocol ClosedLidChangeAuthorizing: AnyObject {
    func authorizeClosedLidChange(enabled: Bool) throws
}

protocol DeviceOwnerAuthenticationContext: AnyObject {
    var localizedCancelTitle: String? { get set }
    func canEvaluateDeviceOwnerAuthentication() -> Bool
    func evaluateDeviceOwnerAuthentication(localizedReason: String, reply: @escaping (Bool, Error?) -> Void)
}

public final class LocalDeviceOwnerAuthorizer: ClosedLidChangeAuthorizing {
    private let contextFactory: () -> DeviceOwnerAuthenticationContext

    public convenience init() {
        self.init(contextFactory: { LAContextDeviceOwnerAdapter() })
    }

    init(contextFactory: @escaping () -> DeviceOwnerAuthenticationContext) {
        self.contextFactory = contextFactory
    }

    public func authorizeClosedLidChange(enabled: Bool) throws {
        let context = contextFactory()
        context.localizedCancelTitle = "Cancel"

        guard context.canEvaluateDeviceOwnerAuthentication() else {
            throw ClosedLidAuthorizationError.deviceOwnerAuthenticationUnavailable
        }

        let semaphore = DispatchSemaphore(value: 0)
        let outcome = LockedResultBox<Result<Void, Error>>(.failure(ClosedLidAuthorizationError.authorizationCanceled))
        let action = enabled ? "enable" : "disable"

        context.evaluateDeviceOwnerAuthentication(localizedReason: "\(action) Closed-Lid Mode") { success, error in
            if success {
                outcome.set(.success(()))
            } else {
                outcome.set(.failure(error ?? ClosedLidAuthorizationError.authorizationCanceled))
            }
            semaphore.signal()
        }

        semaphore.wait()
        try outcome.get().mapError { error in
            if error is ClosedLidAuthorizationError {
                return error
            }
            return ClosedLidAuthorizationError.authorizationCanceled
        }.get()
    }
}

final class LockedResultBox<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class LAContextDeviceOwnerAdapter: DeviceOwnerAuthenticationContext {
    private let context = LAContext()

    var localizedCancelTitle: String? {
        get { context.localizedCancelTitle }
        set { context.localizedCancelTitle = newValue }
    }

    func canEvaluateDeviceOwnerAuthentication() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func evaluateDeviceOwnerAuthentication(localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: localizedReason,
            reply: reply
        )
    }
}

public enum ClosedLidAuthorizationError: LocalizedError, Equatable {
    case deviceOwnerAuthenticationUnavailable
    case authorizationCanceled

    public var errorDescription: String? {
        switch self {
        case .deviceOwnerAuthenticationUnavailable:
            return "macOS authentication is not available for this Mac user. Turn off the Touch ID Helper setting to use the current administrator-password flow."
        case .authorizationCanceled:
            return "macOS approval was not completed. Closed-Lid Mode was not changed."
        }
    }
}

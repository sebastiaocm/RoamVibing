import Foundation
import PrivilegedHelperProtocol

public protocol PrivilegedHelperClienting: AnyObject {
    func setClosedLidBypassEnabled(_ enabled: Bool) throws
}

public final class PrivilegedHelperClosedLidPowerManager: ClosedLidPowerManaging {
    private let authorizer: ClosedLidChangeAuthorizing
    private let client: PrivilegedHelperClienting

    public init(
        authorizer: ClosedLidChangeAuthorizing = LocalDeviceOwnerAuthorizer(),
        client: PrivilegedHelperClienting = XPCPrivilegedHelperClient()
    ) {
        self.authorizer = authorizer
        self.client = client
    }

    public func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        try setClosedLidBypassEnabled(enabled, intent: .userInitiated)
    }

    public func setClosedLidBypassEnabled(_ enabled: Bool, intent: ClosedLidPowerChangeIntent) throws {
        if enabled || intent == .userInitiated {
            try authorizer.authorizeClosedLidChange(enabled: enabled)
        }

        try client.setClosedLidBypassEnabled(enabled)
    }
}

public final class XPCPrivilegedHelperClient: PrivilegedHelperClienting {
    private let machServiceName: String
    private let replyTimeout: TimeInterval
    private let connectionFactory: PrivilegedHelperXPCConnectionMaking
    private let codeSigningRequirementProvider: () throws -> String

    public convenience init(
        machServiceName: String = PrivilegedHelperConstants.machServiceName,
        replyTimeout: TimeInterval = 15
    ) {
        self.init(
            machServiceName: machServiceName,
            replyTimeout: replyTimeout,
            connectionFactory: NSXPCPrivilegedHelperConnectionFactory(),
            codeSigningRequirementProvider: { try Self.defaultCodeSigningRequirement() }
        )
    }

    init(
        machServiceName: String = PrivilegedHelperConstants.machServiceName,
        replyTimeout: TimeInterval = 15,
        connectionFactory: PrivilegedHelperXPCConnectionMaking,
        codeSigningRequirementProvider: @escaping () throws -> String
    ) {
        self.machServiceName = machServiceName
        self.replyTimeout = replyTimeout
        self.connectionFactory = connectionFactory
        self.codeSigningRequirementProvider = codeSigningRequirementProvider
    }

    public func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        let connection = connectionFactory.makeConnection(
            machServiceName: machServiceName,
            codeSigningRequirement: try codeSigningRequirementProvider()
        )
        connection.activate()
        defer { connection.invalidate() }

        let semaphore = DispatchSemaphore(value: 0)
        let outcome = LockedResultBox<Result<Void, Error>>(.failure(PrivilegedHelperClientError.noReply))
        let completion = OneShotCompletionBox()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            completion.complete {
                outcome.set(.failure(PrivilegedHelperClientError.connectionFailed(error.localizedDescription)))
                semaphore.signal()
            }
        }) as? RoamVibingPrivilegedHelperProtocol else {
            throw PrivilegedHelperClientError.invalidProxy
        }

        proxy.setClosedLidBypassEnabled(enabled) { success, message in
            completion.complete {
                if success {
                    outcome.set(.success(()))
                } else {
                    outcome.set(.failure(PrivilegedHelperClientError.requestFailed(message ?? "The helper did not provide more detail.")))
                }
                semaphore.signal()
            }
        }

        guard semaphore.wait(timeout: .now() + replyTimeout) == .success else {
            throw PrivilegedHelperClientError.noReply
        }

        try outcome.get().get()
    }

    private static func defaultCodeSigningRequirement() throws -> String {
        let teamIdentifier = try CurrentProcessCodeSigningIdentity.teamIdentifier()
        return try CodeSigningRequirement.release(
            bundleIdentifier: PrivilegedHelperConstants.helperBundleIdentifier,
            teamIdentifier: teamIdentifier
        )
    }
}

public enum PrivilegedHelperClientError: LocalizedError, Equatable {
    case invalidProxy
    case noReply
    case connectionFailed(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidProxy:
            return "Could not connect to the privileged helper. Closed-Lid Mode was not changed."
        case .noReply:
            return "Privileged helper did not reply in time. Closed-Lid Mode was not changed."
        case let .connectionFailed(message):
            return "Could not connect to the privileged helper. Closed-Lid Mode was not changed. \(message)"
        case let .requestFailed(message):
            return "Privileged helper could not change Closed-Lid Mode. \(message)"
        }
    }
}

protocol PrivilegedHelperXPCConnectionMaking: AnyObject {
    func makeConnection(
        machServiceName: String,
        codeSigningRequirement: String
    ) -> PrivilegedHelperXPCConnecting
}

protocol PrivilegedHelperXPCConnecting: AnyObject {
    func activate()
    func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any
    func invalidate()
}

private final class NSXPCPrivilegedHelperConnectionFactory: PrivilegedHelperXPCConnectionMaking {
    func makeConnection(
        machServiceName: String,
        codeSigningRequirement: String
    ) -> PrivilegedHelperXPCConnecting {
        NSXPCPrivilegedHelperConnection(
            machServiceName: machServiceName,
            codeSigningRequirement: codeSigningRequirement
        )
    }
}

private final class NSXPCPrivilegedHelperConnection: PrivilegedHelperXPCConnecting {
    private let connection: NSXPCConnection

    init(machServiceName: String, codeSigningRequirement: String) {
        connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: RoamVibingPrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(codeSigningRequirement)
    }

    func activate() {
        connection.activate()
    }

    func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any {
        connection.remoteObjectProxyWithErrorHandler(handler)
    }

    func invalidate() {
        connection.invalidate()
    }
}

private final class OneShotCompletionBox {
    private let lock = NSLock()
    private var completed = false

    func complete(_ body: () -> Void) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        body()
    }
}

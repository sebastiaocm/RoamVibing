import XCTest
@testable import LidAwakeCore
import PrivilegedHelperProtocol

final class PrivilegedHelperClosedLidPowerManagerTests: XCTestCase {
    func testManagerAuthorizesBeforeCallingHelper() throws {
        let recorder = ManagerEventRecorder()
        let authorizer = RecordingClosedLidAuthorizer(recorder: recorder)
        let client = RecordingPrivilegedHelperClient(recorder: recorder)
        let manager = PrivilegedHelperClosedLidPowerManager(authorizer: authorizer, client: client)

        try manager.setClosedLidBypassEnabled(true, intent: .userInitiated)

        XCTAssertEqual(recorder.events, ["authorize:true", "helper:true"])
    }

    func testAuthorizationFailureDoesNotCallHelper() {
        let authorizer = RecordingClosedLidAuthorizer(error: ManagerTestError.expected)
        let client = RecordingPrivilegedHelperClient()
        let manager = PrivilegedHelperClosedLidPowerManager(authorizer: authorizer, client: client)

        XCTAssertThrowsError(try manager.setClosedLidBypassEnabled(true, intent: .userInitiated)) { error in
            XCTAssertEqual(error as? ManagerTestError, .expected)
        }

        XCTAssertEqual(client.enabledRequests, [])
    }

    func testSafetyDisableSkipsAuthorizationAndCallsHelper() throws {
        let authorizer = RecordingClosedLidAuthorizer()
        let client = RecordingPrivilegedHelperClient()
        let manager = PrivilegedHelperClosedLidPowerManager(authorizer: authorizer, client: client)

        try manager.setClosedLidBypassEnabled(false, intent: .safety)

        XCTAssertEqual(authorizer.enabledRequests, [])
        XCTAssertEqual(client.enabledRequests, [false])
    }

    func testEnableAlwaysRequiresAuthorizationEvenForSafetyIntent() throws {
        let recorder = ManagerEventRecorder()
        let authorizer = RecordingClosedLidAuthorizer(recorder: recorder)
        let client = RecordingPrivilegedHelperClient(recorder: recorder)
        let manager = PrivilegedHelperClosedLidPowerManager(authorizer: authorizer, client: client)

        try manager.setClosedLidBypassEnabled(true, intent: .safety)

        XCTAssertEqual(recorder.events, ["authorize:true", "helper:true"])
    }

    func testHelperFailureSurfacesFriendlyMessage() {
        let authorizer = RecordingClosedLidAuthorizer()
        let client = RecordingPrivilegedHelperClient(error: PrivilegedHelperClientError.requestFailed("pmset failed"))
        let manager = PrivilegedHelperClosedLidPowerManager(authorizer: authorizer, client: client)

        XCTAssertThrowsError(try manager.setClosedLidBypassEnabled(true, intent: .userInitiated)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("Privileged helper could not change Closed-Lid Mode."))
            XCTAssertTrue(message.contains("pmset failed"))
        }
    }

    func testXPCClientUsesReplyTimeoutInsteadOfWaitingForever() throws {
        let source = try readText("Sources/LidAwakeCore/PrivilegedHelperClosedLidPowerManager.swift")

        XCTAssertTrue(source.contains("replyTimeout: TimeInterval = 15"))
        XCTAssertTrue(source.contains("semaphore.wait(timeout: .now() + replyTimeout)"))
        XCTAssertTrue(source.contains("throw PrivilegedHelperClientError.noReply"))
        XCTAssertFalse(source.contains("semaphore.wait()"))
    }

    func testXPCClientReturnsWhenHelperReplySucceeds() throws {
        let proxy = FakePrivilegedHelperProxy(reply: .success)
        let connection = FakePrivilegedHelperXPCConnection(proxy: proxy)
        let client = makeXPCClient(connection: connection)

        try client.setClosedLidBypassEnabled(true)

        XCTAssertEqual(proxy.enabledRequests, [true])
        XCTAssertTrue(connection.activateCalled)
        XCTAssertTrue(connection.invalidateCalled)
    }

    func testXPCClientMapsHelperFailureReplyToRequestFailed() {
        let proxy = FakePrivilegedHelperProxy(reply: .failure("pmset failed"))
        let connection = FakePrivilegedHelperXPCConnection(proxy: proxy)
        let client = makeXPCClient(connection: connection)

        XCTAssertThrowsError(try client.setClosedLidBypassEnabled(false)) { error in
            XCTAssertEqual(error as? PrivilegedHelperClientError, .requestFailed("pmset failed"))
        }

        XCTAssertEqual(proxy.enabledRequests, [false])
        XCTAssertTrue(connection.invalidateCalled)
    }

    func testXPCClientThrowsInvalidProxyWhenProxyDoesNotMatchHelperProtocol() {
        let connection = FakePrivilegedHelperXPCConnection(proxy: NSObject())
        let client = makeXPCClient(connection: connection)

        XCTAssertThrowsError(try client.setClosedLidBypassEnabled(true)) { error in
            XCTAssertEqual(error as? PrivilegedHelperClientError, .invalidProxy)
        }

        XCTAssertTrue(connection.invalidateCalled)
    }

    func testXPCClientTimesOutWhenHelperDoesNotReply() {
        let proxy = FakePrivilegedHelperProxy(reply: .noReply)
        let connection = FakePrivilegedHelperXPCConnection(proxy: proxy)
        let client = makeXPCClient(connection: connection, replyTimeout: 0.05)

        XCTAssertThrowsError(try client.setClosedLidBypassEnabled(true)) { error in
            XCTAssertEqual(error as? PrivilegedHelperClientError, .noReply)
        }

        XCTAssertEqual(proxy.enabledRequests, [true])
        XCTAssertTrue(connection.invalidateCalled)
    }

    func testXPCClientSurfacesRemoteProxyErrorWithoutWaitingForReplyTimeout() {
        let proxy = FakePrivilegedHelperProxy(reply: .noReply)
        let connection = FakePrivilegedHelperXPCConnection(
            proxy: proxy,
            remoteProxyError: NSError(
                domain: "XPC",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "mach service lookup failed"]
            )
        )
        let client = makeXPCClient(connection: connection, replyTimeout: 1)
        let start = Date()

        XCTAssertThrowsError(try client.setClosedLidBypassEnabled(true)) { error in
            guard let clientError = error as? PrivilegedHelperClientError,
                  case let .connectionFailed(message) = clientError else {
                return XCTFail("Expected connectionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("mach service lookup failed"))
            XCTAssertTrue(((error as? LocalizedError)?.errorDescription ?? "").contains("Could not connect"))
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
        XCTAssertTrue(connection.invalidateCalled)
    }

    func testXPCClientCallbackResultIsProtectedByLock() throws {
        let source = try readText("Sources/LidAwakeCore/PrivilegedHelperClosedLidPowerManager.swift")

        XCTAssertTrue(source.contains("LockedResultBox<Result<Void, Error>>"))
        XCTAssertTrue(source.contains("outcome.set("))
        XCTAssertTrue(source.contains("try outcome.get().get()"))
        XCTAssertFalse(source.contains("var outcome: Result<Void, Error>"))
    }

    private func readText(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeXPCClient(
        connection: FakePrivilegedHelperXPCConnection,
        replyTimeout: TimeInterval = 1
    ) -> XPCPrivilegedHelperClient {
        XPCPrivilegedHelperClient(
            machServiceName: "test.helper",
            replyTimeout: replyTimeout,
            connectionFactory: FakePrivilegedHelperXPCConnectionFactory(connection: connection),
            codeSigningRequirementProvider: { "anchor apple generic" }
        )
    }
}

private final class ManagerEventRecorder {
    var events: [String] = []
}

private final class RecordingClosedLidAuthorizer: ClosedLidChangeAuthorizing {
    private let recorder: ManagerEventRecorder?
    private let error: Error?
    var enabledRequests: [Bool] = []

    init(recorder: ManagerEventRecorder? = nil, error: Error? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func authorizeClosedLidChange(enabled: Bool) throws {
        enabledRequests.append(enabled)
        recorder?.events.append("authorize:\(enabled)")

        if let error {
            throw error
        }
    }
}

private final class RecordingPrivilegedHelperClient: PrivilegedHelperClienting {
    private let recorder: ManagerEventRecorder?
    private let error: Error?
    var enabledRequests: [Bool] = []

    init(recorder: ManagerEventRecorder? = nil, error: Error? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        enabledRequests.append(enabled)
        recorder?.events.append("helper:\(enabled)")

        if let error {
            throw error
        }
    }
}

private enum ManagerTestError: Error, Equatable {
    case expected
}

private final class FakePrivilegedHelperXPCConnectionFactory: PrivilegedHelperXPCConnectionMaking {
    private let connection: FakePrivilegedHelperXPCConnection
    private(set) var requestedMachServiceName: String?
    private(set) var requestedCodeSigningRequirement: String?

    init(connection: FakePrivilegedHelperXPCConnection) {
        self.connection = connection
    }

    func makeConnection(
        machServiceName: String,
        codeSigningRequirement: String
    ) -> PrivilegedHelperXPCConnecting {
        requestedMachServiceName = machServiceName
        requestedCodeSigningRequirement = codeSigningRequirement
        return connection
    }
}

private final class FakePrivilegedHelperXPCConnection: PrivilegedHelperXPCConnecting {
    private let proxy: Any
    private let remoteProxyError: Error?
    private(set) var activateCalled = false
    private(set) var invalidateCalled = false

    init(proxy: Any, remoteProxyError: Error? = nil) {
        self.proxy = proxy
        self.remoteProxyError = remoteProxyError
    }

    func activate() {
        activateCalled = true
    }

    func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any {
        if let remoteProxyError {
            handler(remoteProxyError)
        }
        return proxy
    }

    func invalidate() {
        invalidateCalled = true
    }
}

private final class FakePrivilegedHelperProxy: NSObject, RoamVibingPrivilegedHelperProtocol {
    enum Reply {
        case success
        case failure(String)
        case noReply
    }

    private let reply: Reply
    private(set) var enabledRequests: [Bool] = []

    init(reply: Reply) {
        self.reply = reply
    }

    func setClosedLidBypassEnabled(_ enabled: Bool, withReply replyHandler: @escaping (Bool, String?) -> Void) {
        enabledRequests.append(enabled)

        switch reply {
        case .success:
            replyHandler(true, nil)
        case let .failure(message):
            replyHandler(false, message)
        case .noReply:
            break
        }
    }
}

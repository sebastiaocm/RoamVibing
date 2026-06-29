import XCTest
@testable import LidAwakeCore

final class ClosedLidAuthorizationTests: XCTestCase {
    func testAuthorizeUsesDeviceOwnerPolicyWithClosedLidReason() throws {
        let context = RecordingDeviceOwnerContext(canEvaluate: true, evaluationSucceeds: true)
        let authorizer = LocalDeviceOwnerAuthorizer(contextFactory: { context })

        try authorizer.authorizeClosedLidChange(enabled: true)

        XCTAssertEqual(context.policyName, "deviceOwnerAuthentication")
        XCTAssertEqual(context.reason, "enable Closed-Lid Mode")
        XCTAssertEqual(context.localizedCancelTitle, "Cancel")
    }

    func testAuthorizeUsesDisableReason() throws {
        let context = RecordingDeviceOwnerContext(canEvaluate: true, evaluationSucceeds: true)
        let authorizer = LocalDeviceOwnerAuthorizer(contextFactory: { context })

        try authorizer.authorizeClosedLidChange(enabled: false)

        XCTAssertEqual(context.reason, "disable Closed-Lid Mode")
    }

    func testUnavailableDeviceOwnerAuthenticationThrowsFriendlyError() {
        let context = RecordingDeviceOwnerContext(canEvaluate: false, evaluationSucceeds: false)
        let authorizer = LocalDeviceOwnerAuthorizer(contextFactory: { context })

        XCTAssertThrowsError(try authorizer.authorizeClosedLidChange(enabled: true)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("macOS authentication is not available"))
            XCTAssertTrue(message.contains("current administrator-password flow"))
        }
    }

    func testCanceledDeviceOwnerAuthenticationThrowsFriendlyError() {
        let context = RecordingDeviceOwnerContext(canEvaluate: true, evaluationSucceeds: false)
        let authorizer = LocalDeviceOwnerAuthorizer(contextFactory: { context })

        XCTAssertThrowsError(try authorizer.authorizeClosedLidChange(enabled: false)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("macOS approval was not completed"))
        }
    }

    func testAuthorizeWaitsForDelayedDeviceOwnerCallback() throws {
        let context = DelayedDeviceOwnerContext(canEvaluate: true, evaluationSucceeds: true)
        let authorizer = LocalDeviceOwnerAuthorizer(contextFactory: { context })

        try authorizer.authorizeClosedLidChange(enabled: true)

        XCTAssertEqual(context.reason, "enable Closed-Lid Mode")
    }

    func testAuthorizationCallbackResultIsProtectedByLock() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/LidAwakeCore/ClosedLidAuthorization.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("final class LockedResultBox"))
        XCTAssertTrue(source.contains("private let lock = NSLock()"))
        XCTAssertTrue(source.contains("outcome.set("))
        XCTAssertTrue(source.contains("try outcome.get().mapError"))
        XCTAssertFalse(source.contains("var outcome: Result<Void, Error>"))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class RecordingDeviceOwnerContext: DeviceOwnerAuthenticationContext {
    let canEvaluate: Bool
    let evaluationSucceeds: Bool
    var localizedCancelTitle: String?
    var policyName: String?
    var reason: String?

    init(canEvaluate: Bool, evaluationSucceeds: Bool) {
        self.canEvaluate = canEvaluate
        self.evaluationSucceeds = evaluationSucceeds
    }

    func canEvaluateDeviceOwnerAuthentication() -> Bool {
        policyName = "deviceOwnerAuthentication"
        return canEvaluate
    }

    func evaluateDeviceOwnerAuthentication(localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        reason = localizedReason
        reply(evaluationSucceeds, evaluationSucceeds ? nil : TestError.expected)
    }
}

private final class DelayedDeviceOwnerContext: DeviceOwnerAuthenticationContext {
    let canEvaluate: Bool
    let evaluationSucceeds: Bool
    var localizedCancelTitle: String?
    var reason: String?

    init(canEvaluate: Bool, evaluationSucceeds: Bool) {
        self.canEvaluate = canEvaluate
        self.evaluationSucceeds = evaluationSucceeds
    }

    func canEvaluateDeviceOwnerAuthentication() -> Bool {
        canEvaluate
    }

    func evaluateDeviceOwnerAuthentication(localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        reason = localizedReason
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            reply(self.evaluationSucceeds, self.evaluationSucceeds ? nil : TestError.expected)
        }
    }
}

private enum TestError: Error, Equatable {
    case expected
}

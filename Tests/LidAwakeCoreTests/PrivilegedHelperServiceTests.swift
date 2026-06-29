import Foundation
import XCTest
@testable import PrivilegedHelperCore
@testable import PrivilegedHelperProtocol

final class PrivilegedHelperServiceTests: XCTestCase {
    func testServiceEnableCallsPowerCommandAndRepliesSuccess() {
        let command = RecordingHelperCommand()
        let service = PrivilegedHelperService(powerCommand: command)

        var reply: (success: Bool, message: String?)?
        service.setClosedLidBypassEnabled(true) { success, message in
            reply = (success, message)
        }

        XCTAssertEqual(command.enabledValues, [true])
        XCTAssertEqual(reply?.success, true)
        XCTAssertNil(reply?.message)
    }

    func testServiceFailureRepliesFailureMessage() {
        let command = RecordingHelperCommand(error: PrivilegedHelperPowerCommandError.verificationFailed(expectedValue: "1"))
        let service = PrivilegedHelperService(powerCommand: command)

        var reply: (success: Bool, message: String?)?
        service.setClosedLidBypassEnabled(true) { success, message in
            reply = (success, message)
        }

        XCTAssertEqual(command.enabledValues, [true])
        XCTAssertEqual(reply?.success, false)
        XCTAssertTrue(reply?.message?.contains("SleepDisabled 1") == true)
    }

    func testListenerSetsAppCodeSigningRequirement() throws {
        let requirement = try CodeSigningRequirement.release(
            bundleIdentifier: PrivilegedHelperConstants.appBundleIdentifier,
            teamIdentifier: "TEAM123456"
        )
        let service = PrivilegedHelperService(powerCommand: RecordingHelperCommand())
        let delegate = try PrivilegedHelperListenerDelegate(
            appCodeSigningRequirement: requirement,
            serviceFactory: { service }
        )
        let connection = RecordingXPCConnection()

        XCTAssertTrue(delegate.configure(connection: connection))

        XCTAssertEqual(connection.codeSigningRequirement, requirement)
        XCTAssertNotNil(connection.exportedInterface)
        XCTAssertTrue(connection.exportedObject as AnyObject === service)
        XCTAssertEqual(connection.resumeCallCount, 1)
    }
}

private final class RecordingHelperCommand: PrivilegedHelperPowerCommanding {
    private let error: Error?
    private(set) var enabledValues: [Bool] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        enabledValues.append(enabled)

        if let error {
            throw error
        }
    }
}

private final class RecordingXPCConnection: XPCConnectionConfiguring {
    private(set) var codeSigningRequirement: String?
    private(set) var exportedInterface: NSXPCInterface?
    private(set) var exportedObject: Any?
    private(set) var resumeCallCount = 0

    func setCodeSigningRequirement(_ requirement: String) {
        codeSigningRequirement = requirement
    }

    func setExportedInterface(_ interface: NSXPCInterface) {
        exportedInterface = interface
    }

    func setExportedObject(_ object: Any) {
        exportedObject = object
    }

    func resume() {
        resumeCallCount += 1
    }
}

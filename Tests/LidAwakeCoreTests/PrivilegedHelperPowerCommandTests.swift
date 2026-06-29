import XCTest
@testable import PrivilegedHelperCore

final class PrivilegedHelperPowerCommandTests: XCTestCase {
    func testEnableUsesFixedPmsetArgumentsOnly() throws {
        let runner = RecordingProcessRunner(outputs: ["", "SleepDisabled 1\n"])
        let command = PrivilegedHelperPowerCommand(processRunner: runner)

        try command.setClosedLidBypassEnabled(true)

        XCTAssertEqual(runner.calls, [
            .init(executablePath: "/usr/bin/pmset", arguments: ["-a", "disablesleep", "1"], timeout: 5),
            .init(executablePath: "/usr/bin/pmset", arguments: ["-g"], timeout: 5)
        ])
    }

    func testDisableUsesFixedPmsetArgumentsOnly() throws {
        let runner = RecordingProcessRunner(outputs: ["", "SleepDisabled 0\n"])
        let command = PrivilegedHelperPowerCommand(processRunner: runner)

        try command.setClosedLidBypassEnabled(false)

        XCTAssertEqual(runner.calls, [
            .init(executablePath: "/usr/bin/pmset", arguments: ["-a", "disablesleep", "0"], timeout: 5),
            .init(executablePath: "/usr/bin/pmset", arguments: ["-g"], timeout: 5)
        ])
    }

    func testVerificationFailureThrows() {
        let runner = RecordingProcessRunner(outputs: ["", "SleepDisabled 0\n"])
        let command = PrivilegedHelperPowerCommand(processRunner: runner)

        XCTAssertThrowsError(try command.setClosedLidBypassEnabled(true)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("macOS did not report SleepDisabled 1"))
        }
    }

    func testHelperSourceDoesNotUseShellOrOsascript() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/PrivilegedHelperCore/PrivilegedHelperPowerCommand.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("/bin/sh"))
        XCTAssertFalse(source.contains("/usr/bin/osascript"))
        XCTAssertFalse(source.contains("do shell script"))
        XCTAssertFalse(source.contains("sudo"))
    }

    func testFoundationRunnerTimesOutAndTerminatesHungProcess() {
        var launchedProcess: Process?
        let runner = FoundationPrivilegedHelperProcessRunner { process in
            launchedProcess = process
        }

        XCTAssertThrowsError(try runner.run(executablePath: "/bin/sleep", arguments: ["2"], timeout: 0.05)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("timed out"))
        }
        XCTAssertNotNil(launchedProcess)
        XCTAssertEqual(launchedProcess?.isRunning, false)
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class RecordingProcessRunner: PrivilegedHelperProcessRunning {
    struct Call: Equatable {
        let executablePath: String
        let arguments: [String]
        let timeout: TimeInterval
    }

    var calls: [Call] = []
    var outputs: [String]

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) throws -> String {
        calls.append(.init(executablePath: executablePath, arguments: arguments, timeout: timeout))
        return outputs.removeFirst()
    }
}

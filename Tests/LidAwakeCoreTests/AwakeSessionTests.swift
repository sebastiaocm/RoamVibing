import XCTest
@testable import LidAwakeCore

final class AwakeSessionTests: XCTestCase {
    func testStartingNormalModeAcquiresAssertionsOnly() throws {
        let assertions = RecordingAssertionManager()
        let closedLid = RecordingClosedLidPowerManager()
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)

        try session.start(mode: .normal)

        XCTAssertEqual(assertions.events, [.acquire])
        XCTAssertEqual(closedLid.events, [])
        XCTAssertEqual(session.state, .running(.normal))
    }

    func testStartingClosedLidModeAcquiresAssertionsAndEnablesBypass() throws {
        let assertions = RecordingAssertionManager()
        let closedLid = RecordingClosedLidPowerManager()
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)

        try session.start(mode: .closedLid)

        XCTAssertEqual(assertions.events, [.acquire])
        XCTAssertEqual(closedLid.events, [.setEnabled(true)])
        XCTAssertEqual(closedLid.intentEvents, [.setEnabled(true, .userInitiated)])
        XCTAssertEqual(session.state, .running(.closedLid))
    }

    func testStoppingClosedLidModeDisablesBypassBeforeReleasingAssertions() throws {
        let recorder = EventRecorder()
        let assertions = RecordingAssertionManager(recorder: recorder)
        let closedLid = RecordingClosedLidPowerManager(recorder: recorder)
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)

        try session.start(mode: .closedLid)
        recorder.events.removeAll()
        try session.stop()

        XCTAssertEqual(recorder.events, ["closedLid:false", "assertions:release"])
        XCTAssertEqual(session.state, .stopped)
    }

    func testClosedLidStopFailureKeepsSessionRunningAndAssertionsHeld() throws {
        let assertions = RecordingAssertionManager()
        let closedLid = RecordingClosedLidPowerManager(errorWhenSetting: false)
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)

        try session.start(mode: .closedLid)

        XCTAssertThrowsError(try session.stop()) { error in
            XCTAssertEqual(error as? TestError, .expected)
        }

        XCTAssertEqual(assertions.events, [.acquire])
        XCTAssertEqual(closedLid.events, [.setEnabled(true), .setEnabled(false)])
        XCTAssertEqual(session.state, .running(.closedLid))
    }

    func testSafetyStopPassesSafetyIntentToClosedLidPowerManager() throws {
        let assertions = RecordingAssertionManager()
        let closedLid = RecordingClosedLidPowerManager()
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)

        try session.start(mode: .closedLid)
        closedLid.intentEvents.removeAll()
        try session.stop(intent: .safety)

        XCTAssertEqual(closedLid.intentEvents, [.setEnabled(false, .safety)])
        XCTAssertEqual(closedLid.events, [.setEnabled(true), .setEnabled(false)])
        XCTAssertEqual(session.state, .stopped)
    }

    func testClosedLidEnableFailureRollsBackAssertionsAndLeavesSessionStopped() throws {
        let assertions = RecordingAssertionManager()
        let closedLid = RecordingClosedLidPowerManager(error: TestError.expected)
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)

        XCTAssertThrowsError(try session.start(mode: .closedLid)) { error in
            XCTAssertEqual(error as? TestError, .expected)
        }

        XCTAssertEqual(assertions.events, [.acquire, .release])
        XCTAssertEqual(closedLid.events, [.setEnabled(true)])
        XCTAssertEqual(session.state, .stopped)
    }

    func testStartingDifferentModeStopsPreviousSessionFirst() throws {
        let recorder = EventRecorder()
        let assertions = RecordingAssertionManager(recorder: recorder)
        let closedLid = RecordingClosedLidPowerManager(recorder: recorder)
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)

        try session.start(mode: .normal)
        recorder.events.removeAll()
        try session.start(mode: .closedLid)

        XCTAssertEqual(
            recorder.events,
            [
                "assertions:release",
                "assertions:acquire",
                "closedLid:true"
            ]
        )
        XCTAssertEqual(session.state, .running(.closedLid))
    }

    func testStateReadWaitsForActiveStartOperation() throws {
        let assertions = RecordingAssertionManager()
        let closedLid = BlockingClosedLidPowerManager()
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)
        let startFinished = expectation(description: "start finished")
        let stateReadFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            do {
                try session.start(mode: .closedLid)
            } catch {
                XCTFail("start failed: \(error)")
            }
            startFinished.fulfill()
        }

        XCTAssertEqual(closedLid.waitUntilBlocked(), .success)

        DispatchQueue.global().async {
            _ = session.state
            stateReadFinished.signal()
        }

        let prematureRead = stateReadFinished.wait(timeout: .now() + 0.2)
        XCTAssertEqual(prematureRead, .timedOut)
        if prematureRead != .timedOut {
            closedLid.unblock()
            wait(for: [startFinished], timeout: 1)
            return
        }

        closedLid.unblock()
        wait(for: [startFinished], timeout: 1)
        XCTAssertEqual(stateReadFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(session.state, .running(.closedLid))
    }
}

final class ClosedLidBypassCommandTests: XCTestCase {
    func testBuildsEnableCommandForAdministratorPrompt() {
        let arguments = ClosedLidBypassCommand.osascriptArguments(enabled: true)
        let script = arguments[1]

        XCTAssertEqual(arguments[0], "-e")
        XCTAssertTrue(script.contains("/usr/bin/pmset -a disablesleep 1"))
        XCTAssertTrue(script.contains("/usr/bin/pmset -g"))
        XCTAssertTrue(script.contains("SleepDisabled"))
        XCTAssertTrue(script.contains("$2 != 1"))
        XCTAssertTrue(script.contains("exit 42"))
        XCTAssertTrue(script.contains("with administrator privileges"))
        XCTAssertTrue(script.contains("enable Closed-Lid Mode"))
    }

    func testBuildsDisableCommandForAdministratorPrompt() {
        let arguments = ClosedLidBypassCommand.osascriptArguments(enabled: false)
        let script = arguments[1]

        XCTAssertEqual(arguments[0], "-e")
        XCTAssertTrue(script.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertTrue(script.contains("/usr/bin/pmset -g"))
        XCTAssertTrue(script.contains("SleepDisabled"))
        XCTAssertTrue(script.contains("$2 != 0"))
        XCTAssertTrue(script.contains("exit 42"))
        XCTAssertTrue(script.contains("with administrator privileges"))
        XCTAssertTrue(script.contains("disable Closed-Lid Mode"))
    }

    func testAdminPowerManagerRunsOsascriptWithGeneratedArguments() throws {
        let runner = RecordingCommandRunner()
        let manager = AdminClosedLidPowerManager(commandRunner: runner)

        try manager.setClosedLidBypassEnabled(true)

        XCTAssertEqual(runner.executablePath, "/usr/bin/osascript")
        XCTAssertEqual(
            runner.arguments,
            ClosedLidBypassCommand.osascriptArguments(enabled: true)
        )
    }

    func testAdminPowerManagerThrowsWhenCommandFails() {
        let runner = RecordingCommandRunner(error: TestError.expected)
        let manager = AdminClosedLidPowerManager(commandRunner: runner)

        XCTAssertThrowsError(try manager.setClosedLidBypassEnabled(false)) { error in
            XCTAssertEqual(error as? TestError, .expected)
        }
    }

    func testCommandRunErrorShowsFriendlyMessageForAdministratorAuthenticationFailure() throws {
        let error = CommandRunError(
            executablePath: "/usr/bin/osascript",
            status: 1,
            output: "0:80: execution error: The administrator user name or password was incorrect. (-60005)"
        )

        let description = try XCTUnwrap(error.errorDescription)

        XCTAssertTrue(description.contains("Administrator authentication failed or was canceled."))
        XCTAssertTrue(description.contains("Closed-Lid Mode was not changed."))
        XCTAssertTrue(description.contains("Use Touch ID if macOS offers it"))
        XCTAssertTrue(description.contains("Mac administrator password"))
        XCTAssertFalse(description.contains("/usr/bin/osascript exited with status 1"))
        XCTAssertFalse(description.contains("-60005"))
    }
}

private final class EventRecorder {
    var events: [String] = []
}

private final class RecordingAssertionManager: AssertionManaging {
    enum Event: Equatable {
        case acquire
        case release
    }

    private let recorder: EventRecorder?
    private let error: Error?
    var events: [Event] = []

    init(recorder: EventRecorder? = nil, error: Error? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func acquire() throws {
        events.append(.acquire)
        recorder?.events.append("assertions:acquire")
        if let error {
            throw error
        }
    }

    func release() {
        events.append(.release)
        recorder?.events.append("assertions:release")
    }
}

private final class RecordingClosedLidPowerManager: ClosedLidPowerManaging {
    enum Event: Equatable {
        case setEnabled(Bool)
    }

    enum IntentEvent: Equatable {
        case setEnabled(Bool, ClosedLidPowerChangeIntent)
    }

    private let recorder: EventRecorder?
    private let error: Error?
    private let errorWhenSetting: Bool?
    var events: [Event] = []
    var intentEvents: [IntentEvent] = []

    init(recorder: EventRecorder? = nil, error: Error? = nil, errorWhenSetting: Bool? = nil) {
        self.recorder = recorder
        self.error = error
        self.errorWhenSetting = errorWhenSetting
    }

    func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        try recordSetClosedLidBypassEnabled(enabled)
    }

    func setClosedLidBypassEnabled(_ enabled: Bool, intent: ClosedLidPowerChangeIntent) throws {
        intentEvents.append(.setEnabled(enabled, intent))
        try recordSetClosedLidBypassEnabled(enabled)
    }

    private func recordSetClosedLidBypassEnabled(_ enabled: Bool) throws {
        events.append(.setEnabled(enabled))
        recorder?.events.append("closedLid:\(enabled)")
        if errorWhenSetting == enabled {
            throw TestError.expected
        }
        if let error {
            throw error
        }
    }
}

private final class BlockingClosedLidPowerManager: ClosedLidPowerManaging {
    private let blocked = DispatchSemaphore(value: 0)
    private let unblocker = DispatchSemaphore(value: 0)

    func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        blocked.signal()
        unblocker.wait()
    }

    func waitUntilBlocked() -> DispatchTimeoutResult {
        blocked.wait(timeout: .now() + 1)
    }

    func unblock() {
        unblocker.signal()
    }
}

private enum TestError: Error, Equatable {
    case expected
}

private final class RecordingCommandRunner: CommandRunning {
    private let error: Error?
    var executablePath: String?
    var arguments: [String]?

    init(error: Error? = nil) {
        self.error = error
    }

    func run(executablePath: String, arguments: [String]) throws {
        self.executablePath = executablePath
        self.arguments = arguments

        if let error {
            throw error
        }
    }
}

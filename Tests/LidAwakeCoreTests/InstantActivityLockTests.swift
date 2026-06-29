import XCTest
@testable import LidAwakeCore

final class InstantActivityLockTests: XCTestCase {
    func testArmsAfterSessionHasBeenIdleLongEnough() throws {
        let session = AwakeSession(
            assertions: RecordingAssertionManager(),
            closedLidPower: RecordingClosedLidPowerManager()
        )
        let input = RecordingInputActivityReader(idleSeconds: 5)
        let locker = RecordingScreenLocker()
        let guardrail = InstantActivityLockGuard(
            session: session,
            inputActivityReader: input,
            screenLocker: locker,
            policy: InstantActivityLockPolicy(isEnabled: true, idleArmingDelay: 5)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .armed)
        XCTAssertEqual(input.readCount, 1)
        XCTAssertEqual(locker.lockCount, 0)
    }

    func testLocksWhenActivityIsDetectedAfterArming() throws {
        let session = AwakeSession(
            assertions: RecordingAssertionManager(),
            closedLidPower: RecordingClosedLidPowerManager()
        )
        let input = RecordingInputActivityReader(idleSeconds: 5)
        let locker = RecordingScreenLocker()
        let guardrail = InstantActivityLockGuard(
            session: session,
            inputActivityReader: input,
            screenLocker: locker,
            policy: InstantActivityLockPolicy(isEnabled: true, idleArmingDelay: 5)
        )

        try session.start(mode: .normal)
        XCTAssertEqual(try guardrail.evaluate(), .armed)
        input.idleSeconds = 0.2

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .locked)
        XCTAssertEqual(locker.lockCount, 1)
        XCTAssertEqual(session.state, .stopped)
    }

    func testLocksAndStopsSessionWhenLidOpensAfterBeingClosed() throws {
        let session = AwakeSession(
            assertions: RecordingAssertionManager(),
            closedLidPower: RecordingClosedLidPowerManager()
        )
        let input = RecordingInputActivityReader(idleSeconds: 0.2)
        let lid = RecordingLidStateReader(state: .closed)
        let locker = RecordingScreenLocker()
        let guardrail = InstantActivityLockGuard(
            session: session,
            inputActivityReader: input,
            lidStateReader: lid,
            screenLocker: locker,
            policy: InstantActivityLockPolicy(isEnabled: true, idleArmingDelay: 5)
        )

        try session.start(mode: .normal)
        XCTAssertEqual(try guardrail.evaluate(), .noAction)

        lid.state = .open
        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .locked)
        XCTAssertEqual(locker.lockCount, 1)
        XCTAssertEqual(session.state, .stopped)
    }

    func testDoesNotLockBeforeArming() throws {
        let session = AwakeSession(
            assertions: RecordingAssertionManager(),
            closedLidPower: RecordingClosedLidPowerManager()
        )
        let input = RecordingInputActivityReader(idleSeconds: 0.2)
        let locker = RecordingScreenLocker()
        let guardrail = InstantActivityLockGuard(
            session: session,
            inputActivityReader: input,
            screenLocker: locker,
            policy: InstantActivityLockPolicy(isEnabled: true, idleArmingDelay: 5)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(locker.lockCount, 0)
    }

    func testDisabledPolicyDoesNotReadInputOrLock() throws {
        let session = AwakeSession(
            assertions: RecordingAssertionManager(),
            closedLidPower: RecordingClosedLidPowerManager()
        )
        let input = RecordingInputActivityReader(idleSeconds: 0.1)
        let locker = RecordingScreenLocker()
        let guardrail = InstantActivityLockGuard(
            session: session,
            inputActivityReader: input,
            screenLocker: locker,
            policy: InstantActivityLockPolicy(isEnabled: false, idleArmingDelay: 5)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(input.readCount, 0)
        XCTAssertEqual(locker.lockCount, 0)
    }

    func testStoppedSessionDoesNotReadInputOrLock() throws {
        let input = RecordingInputActivityReader(idleSeconds: 0.1)
        let locker = RecordingScreenLocker()
        let guardrail = InstantActivityLockGuard(
            session: AwakeSession(
                assertions: RecordingAssertionManager(),
                closedLidPower: RecordingClosedLidPowerManager()
            ),
            inputActivityReader: input,
            screenLocker: locker,
            policy: InstantActivityLockPolicy(isEnabled: true, idleArmingDelay: 5)
        )

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(input.readCount, 0)
        XCTAssertEqual(locker.lockCount, 0)
    }

    func testLocksOnlyOncePerSessionUntilReset() throws {
        let session = AwakeSession(
            assertions: RecordingAssertionManager(),
            closedLidPower: RecordingClosedLidPowerManager()
        )
        let input = RecordingInputActivityReader(idleSeconds: 5)
        let locker = RecordingScreenLocker()
        let guardrail = InstantActivityLockGuard(
            session: session,
            inputActivityReader: input,
            screenLocker: locker,
            policy: InstantActivityLockPolicy(isEnabled: true, idleArmingDelay: 5)
        )

        try session.start(mode: .normal)
        XCTAssertEqual(try guardrail.evaluate(), .armed)
        input.idleSeconds = 0.1
        XCTAssertEqual(try guardrail.evaluate(), .locked)
        XCTAssertEqual(session.state, .stopped)
        input.idleSeconds = 5
        XCTAssertEqual(try guardrail.evaluate(), .noAction)
        input.idleSeconds = 0.1
        XCTAssertEqual(try guardrail.evaluate(), .noAction)

        XCTAssertEqual(locker.lockCount, 1)

        try session.start(mode: .normal)
        guardrail.resetForSessionStart()
        input.idleSeconds = 5
        XCTAssertEqual(try guardrail.evaluate(), .armed)
        input.idleSeconds = 0.1
        XCTAssertEqual(try guardrail.evaluate(), .locked)
        XCTAssertEqual(locker.lockCount, 2)
    }

    func testAutomaticActivityLockPathUsesSafetyStopIntent() throws {
        let source = try readText("Sources/LidAwakeCore/InstantActivityLock.swift")

        XCTAssertTrue(source.contains("session.stop(intent: .safety)"))
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
}

final class ScreenLockCommandTests: XCTestCase {
    func testScreenLockerUsesDyldResolvedLockFunctionInsteadOfRemovedCGSessionBinary() throws {
        let source = try readText("Sources/LidAwakeCore/InstantActivityLock.swift")

        XCTAssertTrue(source.contains("/System/Library/PrivateFrameworks/login.framework/login"))
        XCTAssertTrue(source.contains("SACLockScreenImmediate"))
        XCTAssertTrue(source.contains("dlopen"))
        XCTAssertTrue(source.contains("dlsym"))
        XCTAssertFalse(source.contains("CGSession"))
        XCTAssertFalse(source.contains("Menu Extras/User.menu"))
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
}

private final class RecordingInputActivityReader: InputActivityReadingProviding {
    var idleSeconds: TimeInterval?
    private(set) var readCount = 0

    init(idleSeconds: TimeInterval?) {
        self.idleSeconds = idleSeconds
    }

    func secondsSinceLastKeyboardOrMouseInput() -> TimeInterval? {
        readCount += 1
        return idleSeconds
    }
}

private final class RecordingLidStateReader: LidStateProviding {
    var state: LidState

    init(state: LidState) {
        self.state = state
    }

    func currentLidState() -> LidState {
        state
    }
}

private final class RecordingScreenLocker: ScreenLocking {
    private(set) var lockCount = 0

    func lockScreen() throws {
        lockCount += 1
    }
}

private final class RecordingAssertionManager: AssertionManaging {
    func acquire() throws {}
    func release() {}
}

private final class RecordingClosedLidPowerManager: ClosedLidPowerManaging {
    func setClosedLidBypassEnabled(_ enabled: Bool) throws {}
}

import XCTest
@testable import LidAwakeCore

final class ThermalSafetyTests: XCTestCase {
    func testSeriousThermalPressureStopsClosedLidSessionWithSafetyIntent() throws {
        let assertions = ThermalTestAssertionManager()
        let closedLid = ThermalTestClosedLidPowerManager()
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)
        let reader = RecordingThermalStateReader(state: .serious)
        let guardrail = ThermalSafetyGuard(
            session: session,
            thermalStateReader: reader,
            policy: ThermalSafetyPolicy(isEnabled: true)
        )

        try session.start(mode: .closedLid)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .stoppedSession(state: .serious))
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(assertions.events, [.acquire, .release])
        XCTAssertEqual(closedLid.events, [
            .init(enabled: true, intent: .userInitiated),
            .init(enabled: false, intent: .safety)
        ])
    }

    func testCriticalThermalPressureStopsNormalSession() throws {
        let assertions = ThermalTestAssertionManager()
        let session = AwakeSession(
            assertions: assertions,
            closedLidPower: ThermalTestClosedLidPowerManager()
        )
        let guardrail = ThermalSafetyGuard(
            session: session,
            thermalStateReader: RecordingThermalStateReader(state: .critical),
            policy: ThermalSafetyPolicy(isEnabled: true)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .stoppedSession(state: .critical))
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(assertions.events, [.acquire, .release])
    }

    func testNominalAndFairThermalPressureDoNotStopSession() throws {
        for state in [ThermalPressureState.nominal, .fair] {
            let assertions = ThermalTestAssertionManager()
            let session = AwakeSession(
                assertions: assertions,
                closedLidPower: ThermalTestClosedLidPowerManager()
            )
            let guardrail = ThermalSafetyGuard(
                session: session,
                thermalStateReader: RecordingThermalStateReader(state: state),
                policy: ThermalSafetyPolicy(isEnabled: true)
            )

            try session.start(mode: .normal)

            let result = try guardrail.evaluate()

            XCTAssertEqual(result, .noAction)
            XCTAssertEqual(session.state, .running(.normal))
            XCTAssertEqual(assertions.events, [.acquire])
        }
    }

    func testDisabledPolicyDoesNotReadThermalStateOrStopSession() throws {
        let assertions = ThermalTestAssertionManager()
        let session = AwakeSession(
            assertions: assertions,
            closedLidPower: ThermalTestClosedLidPowerManager()
        )
        let reader = RecordingThermalStateReader(state: .critical)
        let guardrail = ThermalSafetyGuard(
            session: session,
            thermalStateReader: reader,
            policy: ThermalSafetyPolicy(isEnabled: false)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertEqual(session.state, .running(.normal))
        XCTAssertEqual(assertions.events, [.acquire])
    }

    func testStoppedSessionDoesNotReadThermalState() throws {
        let reader = RecordingThermalStateReader(state: .critical)
        let guardrail = ThermalSafetyGuard(
            session: AwakeSession(
                assertions: ThermalTestAssertionManager(),
                closedLidPower: ThermalTestClosedLidPowerManager()
            ),
            thermalStateReader: reader,
            policy: ThermalSafetyPolicy(isEnabled: true)
        )

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(reader.readCount, 0)
    }

    func testThermalSafetyUsesSafetyStopIntent() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/LidAwakeCore/ThermalSafety.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("session.stop(intent: .safety)"))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class RecordingThermalStateReader: ThermalStateProviding {
    private let state: ThermalPressureState
    private(set) var readCount = 0

    init(state: ThermalPressureState) {
        self.state = state
    }

    func currentThermalState() -> ThermalPressureState {
        readCount += 1
        return state
    }
}

private final class ThermalTestAssertionManager: AssertionManaging {
    enum Event: Equatable {
        case acquire
        case release
    }

    var events: [Event] = []

    func acquire() throws {
        events.append(.acquire)
    }

    func release() {
        events.append(.release)
    }
}

private final class ThermalTestClosedLidPowerManager: ClosedLidPowerManaging {
    struct Event: Equatable {
        let enabled: Bool
        let intent: ClosedLidPowerChangeIntent
    }

    var events: [Event] = []

    func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        events.append(.init(enabled: enabled, intent: .userInitiated))
    }

    func setClosedLidBypassEnabled(_ enabled: Bool, intent: ClosedLidPowerChangeIntent) throws {
        events.append(.init(enabled: enabled, intent: intent))
    }
}

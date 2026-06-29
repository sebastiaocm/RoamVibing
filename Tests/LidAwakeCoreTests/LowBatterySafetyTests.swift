import XCTest
@testable import LidAwakeCore

final class LowBatterySafetyTests: XCTestCase {
    func testEnabledPolicyStopsRunningSessionWhenBatteryIsAtThreshold() throws {
        let assertions = BatteryTestAssertionManager()
        let closedLid = BatteryTestClosedLidPowerManager()
        let session = AwakeSession(assertions: assertions, closedLidPower: closedLid)
        let battery = RecordingBatteryReader(reading: BatteryReading(percentage: 20, isRunningOnBattery: true))
        let guardrail = LowBatteryGuard(
            session: session,
            batteryReader: battery,
            policy: LowBatteryPolicy(isEnabled: true, thresholdPercentage: 20)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .stoppedSession(percentage: 20, threshold: 20))
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(assertions.events, [.acquire, .release])
    }

    func testDisabledPolicyDoesNotStopSessionBelowThreshold() throws {
        let assertions = BatteryTestAssertionManager()
        let session = AwakeSession(
            assertions: assertions,
            closedLidPower: BatteryTestClosedLidPowerManager()
        )
        let battery = RecordingBatteryReader(reading: BatteryReading(percentage: 10, isRunningOnBattery: true))
        let guardrail = LowBatteryGuard(
            session: session,
            batteryReader: battery,
            policy: LowBatteryPolicy(isEnabled: false, thresholdPercentage: 20)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(session.state, .running(.normal))
        XCTAssertEqual(assertions.events, [.acquire])
    }

    func testPolicyDoesNotStopSessionWhenConnectedToPower() throws {
        let assertions = BatteryTestAssertionManager()
        let session = AwakeSession(
            assertions: assertions,
            closedLidPower: BatteryTestClosedLidPowerManager()
        )
        let battery = RecordingBatteryReader(reading: BatteryReading(percentage: 10, isRunningOnBattery: false))
        let guardrail = LowBatteryGuard(
            session: session,
            batteryReader: battery,
            policy: LowBatteryPolicy(isEnabled: true, thresholdPercentage: 20)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(session.state, .running(.normal))
        XCTAssertEqual(assertions.events, [.acquire])
    }

    func testPolicyDoesNotStopSessionAboveThreshold() throws {
        let assertions = BatteryTestAssertionManager()
        let session = AwakeSession(
            assertions: assertions,
            closedLidPower: BatteryTestClosedLidPowerManager()
        )
        let battery = RecordingBatteryReader(reading: BatteryReading(percentage: 21, isRunningOnBattery: true))
        let guardrail = LowBatteryGuard(
            session: session,
            batteryReader: battery,
            policy: LowBatteryPolicy(isEnabled: true, thresholdPercentage: 20)
        )

        try session.start(mode: .normal)

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(session.state, .running(.normal))
        XCTAssertEqual(assertions.events, [.acquire])
    }

    func testPolicyDoesNotReadBatteryWhenSessionIsStopped() throws {
        let battery = RecordingBatteryReader(reading: BatteryReading(percentage: 10, isRunningOnBattery: true))
        let guardrail = LowBatteryGuard(
            session: AwakeSession(
                assertions: BatteryTestAssertionManager(),
                closedLidPower: BatteryTestClosedLidPowerManager()
            ),
            batteryReader: battery,
            policy: LowBatteryPolicy(isEnabled: true, thresholdPercentage: 20)
        )

        let result = try guardrail.evaluate()

        XCTAssertEqual(result, .noAction)
        XCTAssertEqual(battery.readCount, 0)
    }

    func testAutomaticSafetyPathUsesSafetyStopIntent() throws {
        let source = try readText("Sources/LidAwakeCore/LowBatterySafety.swift")

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

private final class RecordingBatteryReader: BatteryReadingProviding {
    private let reading: BatteryReading?
    private(set) var readCount = 0

    init(reading: BatteryReading?) {
        self.reading = reading
    }

    func currentBatteryReading() -> BatteryReading? {
        readCount += 1
        return reading
    }
}

private final class BatteryTestAssertionManager: AssertionManaging {
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

private final class BatteryTestClosedLidPowerManager: ClosedLidPowerManaging {
    func setClosedLidBypassEnabled(_ enabled: Bool) throws {}
}

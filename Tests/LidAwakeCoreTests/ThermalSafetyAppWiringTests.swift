import XCTest

final class ThermalSafetyAppWiringTests: XCTestCase {
    func testMacThermalStateReaderUsesPublicProcessInfoThermalStateOnly() throws {
        let source = try readText("Sources/LidAwake/MacThermalStateReader.swift")

        XCTAssertTrue(source.contains("ProcessInfo.processInfo.thermalState"))
        XCTAssertTrue(source.contains("case .nominal:"))
        XCTAssertTrue(source.contains("case .fair:"))
        XCTAssertTrue(source.contains("case .serious:"))
        XCTAssertTrue(source.contains("case .critical:"))
        XCTAssertTrue(source.contains("@unknown default:"))
        XCTAssertTrue(source.contains("return .critical"))
        XCTAssertFalse(source.contains("SMC"))
        XCTAssertFalse(source.contains("IOServiceGetMatchingService"))
        XCTAssertFalse(source.contains("IORegistryEntry"))
        XCTAssertFalse(source.contains("IOHID"))
    }

    func testThermalSafetySettingsDefaultToEnabled() throws {
        let source = try readText("Sources/LidAwake/ThermalSafetySettingsStore.swift")

        XCTAssertTrue(source.contains("ThermalSafety.isEnabled"))
        XCTAssertTrue(source.contains("ThermalSafetyPolicy.default.isEnabled"))
        XCTAssertTrue(source.contains("defaults.object(forKey: Key.isEnabled) == nil"))
        XCTAssertTrue(source.contains("defaults.set(newValue.isEnabled, forKey: Key.isEnabled)"))
    }

    func testAppDelegateWiresThermalSafetyTimerAndGuard() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("private enum ThermalSafety"))
        XCTAssertTrue(source.contains("static let checkInterval: TimeInterval = 30"))
        XCTAssertTrue(source.contains("private let thermalSafetySettings = ThermalSafetySettingsStore()"))
        XCTAssertTrue(source.contains("private let thermalStateReader = MacThermalStateReader()"))
        XCTAssertTrue(source.contains("private var thermalSafetyTimer: Timer?"))
        XCTAssertTrue(source.contains("private var isShowingThermalSafetyAlert = false"))
        XCTAssertTrue(source.contains("private lazy var thermalSafetyGuard = makeThermalSafetyGuard()"))
        XCTAssertTrue(source.contains("private func makeThermalSafetyGuard() -> ThermalSafetyGuard"))
        XCTAssertTrue(source.contains("thermalStateReader: thermalStateReader"))
        XCTAssertTrue(source.contains("policy: thermalSafetySettings.policy"))
        XCTAssertTrue(source.contains("startThermalSafetyTimer()"))
        XCTAssertTrue(source.contains("thermalSafetyTimer?.invalidate()"))
        XCTAssertTrue(source.contains("private func evaluateThermalSafety()"))
        XCTAssertTrue(source.contains("thermalSafetyGuard.policy = thermalSafetySettings.policy"))
        XCTAssertTrue(source.contains("showThermalSafetyStoppedAlert(state: state)"))
    }

    func testAppDelegateBlocksStartingSessionDuringSeriousThermalPressure() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("if batterySafetyShouldBlockStartingSession() || thermalSafetyShouldBlockStartingSession()"))
        XCTAssertTrue(source.contains("private func thermalSafetyShouldBlockStartingSession() -> Bool"))
        XCTAssertTrue(source.contains("state.shouldStopRoamVibingSession"))
        XCTAssertTrue(source.contains("title: \"Thermal Safety Blocked RoamVibing Session\""))
        XCTAssertTrue(source.contains("macOS reports \\(thermalStateDescription(state)) thermal pressure"))
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

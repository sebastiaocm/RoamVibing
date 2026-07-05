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
        let thermalSafetyEnum = try section(
            in: source,
            from: "private enum ThermalSafety",
            to: "private enum InstantLock"
        )

        XCTAssertTrue(source.contains("private enum ThermalSafety"))
        XCTAssertTrue(thermalSafetyEnum.contains("static let checkInterval: TimeInterval = 30"))
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
        let blockStart = try section(
            in: source,
            from: "private func thermalSafetyShouldBlockStartingSession()",
            to: "private func showLowBatteryStoppedAlert"
        )

        XCTAssertTrue(source.contains("if batterySafetyShouldBlockStartingSession() || thermalSafetyShouldBlockStartingSession()"))
        XCTAssertTrue(blockStart.contains("state.shouldStopRoamVibingSession"))
        XCTAssertTrue(blockStart.contains("title: \"Thermal Safety Blocked RoamVibing Session\""))
        XCTAssertTrue(blockStart.contains("macOS reports \\(thermalStateDescription(state)) thermal pressure"))
        XCTAssertTrue(blockStart.contains("Thermal Safety uses macOS thermal pressure, not raw CPU/GPU temperatures."))
    }

    func testAppDelegateWiresThermalSafetySettingsCheckbox() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")
        let showSettings = try section(
            in: source,
            from: "@objc private func showSettings()",
            to: "@objc private func disableClosedLidBypassFromSettings"
        )

        XCTAssertTrue(showSettings.contains("let thermalPolicy = thermalSafetySettings.policy"))
        XCTAssertTrue(showSettings.contains("let thermalCheckbox = NSButton(checkboxWithTitle: \"Enabled\", target: nil, action: nil)"))
        XCTAssertTrue(showSettings.contains("thermalCheckbox.state = thermalPolicy.isEnabled ? .on : .off"))
        XCTAssertTrue(showSettings.contains("thermalCheckbox.setAccessibilityLabel(\"Enable Thermal Safety\")"))
        XCTAssertTrue(showSettings.contains("thermalCheckbox.setAccessibilityHelp(\"Uses macOS thermal pressure to stop the RoamVibing session at serious or critical pressure. It releases wake blockers so the Mac can cool down and sleep normally, and it does not read raw CPU or GPU temperatures.\")"))
        XCTAssertTrue(showSettings.contains("title: \"Thermal Safety\""))
        XCTAssertTrue(showSettings.contains("description: \"Uses macOS thermal pressure to stop the RoamVibing session at serious or critical pressure. RoamVibing releases wake blockers so the Mac can cool down and sleep normally. It does not read raw CPU or GPU temperatures.\""))
        XCTAssertTrue(showSettings.contains("thermalSafetySettings.policy = ThermalSafetyPolicy(isEnabled: thermalCheckbox.state == .on)"))
        XCTAssertTrue(showSettings.contains("thermalSafetyGuard.policy = thermalSafetySettings.policy"))
        XCTAssertTrue(showSettings.contains("evaluateBatterySafety()\n        evaluateThermalSafety()"))
    }

    func testAppDelegateRateLimitsThermalSafetyErrorsUntilSuccessfulEvaluation() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")
        let evaluateThermalSafety = try section(
            in: source,
            from: "private func evaluateThermalSafety()",
            to: "private func evaluateInstantActivityLock()"
        )

        XCTAssertTrue(source.contains("private var hasShownThermalSafetyError = false"))
        XCTAssertTrue(evaluateThermalSafety.contains("case .noAction:\n                hasShownThermalSafetyError = false\n                return"))
        XCTAssertTrue(evaluateThermalSafety.contains("case let .stoppedSession(state):\n                hasShownThermalSafetyError = false"))
        XCTAssertTrue(evaluateThermalSafety.contains("if hasShownThermalSafetyError {\n                return\n            }"))
        XCTAssertTrue(evaluateThermalSafety.contains("hasShownThermalSafetyError = true"))
        XCTAssertTrue(evaluateThermalSafety.contains("presentError(error, title: \"Could Not Apply Thermal Safety\")"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        let startRange = try XCTUnwrap(source.range(of: start))
        let endRange = try XCTUnwrap(source[startRange.upperBound...].range(of: end))
        return String(source[startRange.lowerBound..<endRange.lowerBound])
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

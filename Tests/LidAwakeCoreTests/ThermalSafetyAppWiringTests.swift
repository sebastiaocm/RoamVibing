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

import XCTest
@testable import PrivilegedHelperProtocol

final class PrivilegedHelperProtocolTests: XCTestCase {
    func testHelperConstantsUseFixedLocalIdentifiers() {
        XCTAssertEqual(PrivilegedHelperConstants.launchdLabel, "com.local.RoamVibing.PrivilegedHelper")
        XCTAssertEqual(PrivilegedHelperConstants.machServiceName, "com.local.RoamVibing.PrivilegedHelper")
        XCTAssertEqual(PrivilegedHelperConstants.launchDaemonPlistName, "com.local.RoamVibing.PrivilegedHelper.plist")
        XCTAssertEqual(PrivilegedHelperConstants.helperExecutableName, "RoamVibingPrivilegedHelper")
    }

    func testReleaseCodeSigningRequirementIsTeamAnchored() throws {
        let requirement = try CodeSigningRequirement.release(
            bundleIdentifier: "com.local.RoamVibing",
            teamIdentifier: "TEAM123456"
        )

        XCTAssertEqual(
            requirement,
            #"anchor apple generic and identifier "com.local.RoamVibing" and certificate leaf[subject.OU] = "TEAM123456""#
        )
    }

    func testDebugCodeSigningRequirementIsCdHashScoped() throws {
        let requirement = try CodeSigningRequirement.adHocDebug(
            bundleIdentifier: "com.local.RoamVibing",
            cdHash: "A93E5A57BEE5753AA6CE6DBA3D60897251E65AE6"
        )

        XCTAssertEqual(
            requirement,
            #"identifier "com.local.RoamVibing" and cdhash H"A93E5A57BEE5753AA6CE6DBA3D60897251E65AE6""#
        )
    }

    func testRejectsIdentifierOnlyRequirement() {
        XCTAssertThrowsError(try CodeSigningRequirement.validate(#"identifier "com.local.RoamVibing""#)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("identifier-only"))
        }
    }

    func testRejectsReleaseRequirementWithoutTeamAnchor() {
        XCTAssertThrowsError(try CodeSigningRequirement.validate(#"anchor apple generic and identifier "com.local.RoamVibing""#)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("Team ID"))
        }
    }

    func testRejectsMalformedRequirementString() {
        XCTAssertThrowsError(try CodeSigningRequirement.validate(#"anchor apple generic and identifier "com.local.RoamVibing"#)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("compile"))
        }
    }

    func testRejectsRequirementWithInjectedOrBranch() {
        XCTAssertThrowsError(
            try CodeSigningRequirement.validate(#"identifier "com.local.RoamVibing" or cdhash H"A93E5A57BEE5753AA6CE6DBA3D60897251E65AE6""#)
        )
    }

    func testReleaseRejectsInjectedBundleIdentifier() {
        XCTAssertThrowsError(
            try CodeSigningRequirement.release(
                bundleIdentifier: #"com.local.RoamVibing" or identifier "com.attacker.App"#,
                teamIdentifier: "TEAM123456"
            )
        )
    }

    func testReleaseRejectsMalformedTeamIdentifier() {
        XCTAssertThrowsError(
            try CodeSigningRequirement.release(
                bundleIdentifier: "com.local.RoamVibing",
                teamIdentifier: "team123456"
            )
        )
    }

    func testDebugRejectsMalformedCdHash() {
        XCTAssertThrowsError(
            try CodeSigningRequirement.adHocDebug(
                bundleIdentifier: "com.local.RoamVibing",
                cdHash: "A93E5A57BEE5753AA6CE6DBA3D60897251E65AEZ"
            )
        )
    }

    func testProtocolExposesOnlyClosedLidBypassMutation() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Sources/PrivilegedHelperProtocol/PrivilegedHelperProtocol.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("setClosedLidBypassEnabled"))
        XCTAssertFalse(source.contains("currentSleepDisabledState"))
        XCTAssertFalse(source.contains("withReply reply: @escaping (NSNumber"))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

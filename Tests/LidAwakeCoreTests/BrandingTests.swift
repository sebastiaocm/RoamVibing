import XCTest

final class BrandingTests: XCTestCase {
    private let appName = "RoamVibing"
    private let subtitle = "Keep coding when the lid closes."

    func testBundleMetadataUsesCommercialBranding() throws {
        let infoURL = projectRoot()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Info.plist")

        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let info = try XCTUnwrap(plist as? [String: Any])

        XCTAssertEqual(info["CFBundleName"] as? String, appName)
        XCTAssertEqual(info["CFBundleExecutable"] as? String, appName)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.local.RoamVibing")
        XCTAssertTrue(
            try XCTUnwrap(info["NSAppleEventsUsageDescription"] as? String)
                .contains(appName)
        )
    }

    func testBuildScriptPackagesCommercialAppName() throws {
        let scriptURL = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-app.sh")

        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("APP_DIR=\"$ROOT_DIR/dist/RoamVibing.app\""))
        XCTAssertTrue(script.contains("ZIP_FILE=\"$ROOT_DIR/dist/RoamVibing.app.zip\""))
        XCTAssertTrue(script.contains("STAGING_APP=\"/private/tmp/RoamVibingBuild/RoamVibing.app\""))
        XCTAssertTrue(script.contains("VERIFY_APP=\"$VERIFY_DIR/RoamVibing.app\""))
        XCTAssertTrue(script.contains(".build/release/RoamVibing"))
        XCTAssertTrue(script.contains("\"$STAGING_CONTENTS_DIR/MacOS/RoamVibing\""))
    }

    func testDocsAndMenuSourceUseCommercialBranding() throws {
        let root = projectRoot()
        let readme = try String(
            contentsOf: root.appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: root
                .appendingPathComponent("Sources")
                .appendingPathComponent("LidAwake")
                .appendingPathComponent("AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(readme.contains("# \(appName)"))
        XCTAssertTrue(readme.contains(subtitle))
        XCTAssertTrue(appDelegate.contains(appName))
        XCTAssertTrue(appDelegate.contains(subtitle))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

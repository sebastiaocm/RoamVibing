import XCTest

final class IconAssetTests: XCTestCase {
    func testBundleMetadataDeclaresRoamVibingIcon() throws {
        let infoURL = projectRoot()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Info.plist")

        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let info = try XCTUnwrap(plist as? [String: Any])

        XCTAssertEqual(info["CFBundleIconFile"] as? String, "RoamVibingIcon")
    }

    func testMenuBarUsesCustomCoderIconInsteadOfBoltSymbol() throws {
        let appDelegateURL = projectRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("LidAwake")
            .appendingPathComponent("AppDelegate.swift")
        let source = try String(contentsOf: appDelegateURL, encoding: .utf8)

        XCTAssertTrue(source.contains("StatusIconFactory.makeCoderIcon"))
        XCTAssertFalse(source.contains("bolt.circle"))
    }

    func testMenuBarButtonUsesIconOnlyWithoutVisibleBrandText() throws {
        let appDelegateURL = projectRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("LidAwake")
            .appendingPathComponent("AppDelegate.swift")
        let source = try String(contentsOf: appDelegateURL, encoding: .utf8)

        XCTAssertTrue(source.contains("button.imagePosition = .imageOnly"))
        XCTAssertFalse(source.contains("menuBarTitle"))
        XCTAssertFalse(source.contains("button.title = Brand.menuBarTitle"))
        XCTAssertTrue(source.contains("button.setAccessibilityLabel(Brand.appName)"))
    }

    func testLogoSourceAndIconGeneratorArePresent() throws {
        let root = projectRoot()
        let logoURL = root
            .appendingPathComponent("Resources")
            .appendingPathComponent("RoamVibingLogo.svg")
        let generatorURL = root
            .appendingPathComponent("scripts")
            .appendingPathComponent("generate-icons.swift")

        let logo = try String(contentsOf: logoURL, encoding: .utf8)
        let generator = try String(contentsOf: generatorURL, encoding: .utf8)

        XCTAssertTrue(logo.contains("<svg"))
        XCTAssertTrue(logo.contains("RoamVibing"))
        XCTAssertTrue(generator.contains("RoamVibingIcon.iconset"))
        XCTAssertTrue(generator.contains("RoamVibingStatusTemplateOn.png"))
        XCTAssertTrue(generator.contains("drawCoderMark"))
    }

    func testBuildScriptGeneratesAndPackagesIconAssets() throws {
        let scriptURL = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("generate-icons.swift"))
        XCTAssertTrue(script.contains("iconutil -c icns"))
        XCTAssertTrue(script.contains("RoamVibingIcon.icns"))
        XCTAssertTrue(script.contains("RoamVibingStatusTemplateOn.png"))
        XCTAssertTrue(script.contains("RoamVibingStatusTemplateOff.png"))
        XCTAssertTrue(script.contains("RoamVibingLogo.svg"))
    }

    func testReadmeDescribesCoderIcon() throws {
        let readmeURL = projectRoot().appendingPathComponent("README.md")
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        XCTAssertTrue(readme.contains("coder-at-laptop icon"))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

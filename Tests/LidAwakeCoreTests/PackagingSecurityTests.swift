import XCTest

final class PackagingSecurityTests: XCTestCase {
    func testAppSourceDoesNotUseNetworkOrRemoteControlApis() throws {
        let root = projectRoot()
        let sourcePaths = [
            "Sources/LidAwake",
            "Sources/LidAwakeCore"
        ]
        let source = try sourcePaths
            .map { path in
                try allSwiftSource(under: root.appendingPathComponent(path))
            }
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("URLSession"))
        XCTAssertFalse(source.contains("NWListener"))
        XCTAssertFalse(source.contains("NWConnection"))
        XCTAssertFalse(source.contains("NSSocket"))
        XCTAssertFalse(source.contains("CFNetwork"))
        XCTAssertFalse(source.contains("CGEventTapCreate"))
        XCTAssertFalse(source.contains("AXIsProcessTrusted"))
    }

    func testBuildScriptSignsTheAppWithoutSandboxEntitlements() throws {
        let scriptURL = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-app.sh")

        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertFalse(script.contains("ENTITLEMENTS_FILE="))
        XCTAssertFalse(script.contains("--entitlements"))
        XCTAssertTrue(script.contains("codesign --force --sign - \"$STAGING_APP\""))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict \"$STAGING_APP\""))
        XCTAssertTrue(script.contains("xattr -d com.apple.FinderInfo \"$APP_DIR\""))
        XCTAssertTrue(script.contains("xattr -d 'com.apple.fileprovider.fpfs#P' \"$APP_DIR\""))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict \"$APP_DIR\""))
        XCTAssertTrue(script.contains("ditto -c -k --keepParent --norsrc \"$STAGING_APP\" \"$ZIP_FILE\""))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict \"$VERIFY_APP\""))
    }

    func testBuildScriptPackagesPrivilegedHelperOnlyWhenExplicitlyEnabled() throws {
        let scriptURL = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-app.sh")

        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let helperEnabledBlocks = helperEnabledIfBlocks(in: script)
        let gatedHelperBuildCopyAndSigning = helperEnabledBlocks.joined(separator: "\n")

        XCTAssertTrue(script.contains("ROAMVIBING_ENABLE_PRIVILEGED_HELPER"))
        XCTAssertTrue(script.contains("ROAMVIBING_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("Contents/Library/LaunchDaemons"))
        XCTAssertTrue(script.contains("RoamVibingPrivilegedHelper"))
        XCTAssertTrue(gatedHelperBuildCopyAndSigning.contains("swift build -c release --product \"$HELPER_EXECUTABLE_NAME\""))
        XCTAssertTrue(gatedHelperBuildCopyAndSigning.contains("cp -f \"$ROOT_DIR/.build/release/$HELPER_EXECUTABLE_NAME\""))
        XCTAssertTrue(gatedHelperBuildCopyAndSigning.contains("codesign --force --options runtime --sign \"$ROAMVIBING_SIGN_IDENTITY\" --identifier \"$HELPER_LABEL\" \"$HELPER_STAGING_DAEMON_DIR/$HELPER_EXECUTABLE_NAME\""))
        XCTAssertTrue(gatedHelperBuildCopyAndSigning.contains("codesign --force --options runtime --sign \"$ROAMVIBING_SIGN_IDENTITY\" \"$STAGING_APP\""))
        XCTAssertTrue(script.contains("Helper-enabled builds must be installed in /Applications before helper registration"))
        XCTAssertTrue(script.contains("ROAMVIBING_NOTARY_KEYCHAIN_PROFILE"))
        XCTAssertTrue(script.contains("ROAMVIBING_SKIP_NOTARIZATION"))
        XCTAssertTrue(script.contains("For local-only helper testing, set ROAMVIBING_SKIP_NOTARIZATION=1"))
        XCTAssertTrue(script.contains("Skipping notarization for a local-only helper build. Do not distribute this build."))
        XCTAssertTrue(gatedHelperBuildCopyAndSigning.contains("xcrun notarytool submit"))
        XCTAssertTrue(gatedHelperBuildCopyAndSigning.contains("xcrun stapler staple"))
        XCTAssertTrue(gatedHelperBuildCopyAndSigning.contains("spctl -a -vv"))
    }

    func testPrivilegedHelperSourceDoesNotUseNetworkOrRemoteControlApis() throws {
        let root = projectRoot()
        let sourcePaths = [
            "Sources/PrivilegedHelperCore",
            "Sources/RoamVibingPrivilegedHelper"
        ]
        let source = try sourcePaths
            .map { path in
                try allSwiftSource(under: root.appendingPathComponent(path))
            }
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("URLSession"))
        XCTAssertFalse(source.contains("NWListener"))
        XCTAssertFalse(source.contains("NWConnection"))
        XCTAssertFalse(source.contains("NSSocket"))
        XCTAssertFalse(source.contains("CFNetwork"))
        XCTAssertFalse(source.contains("CGEventTapCreate"))
        XCTAssertFalse(source.contains("AXIsProcessTrusted"))
        XCTAssertFalse(source.contains("/bin/sh"))
        XCTAssertFalse(source.contains("/usr/bin/osascript"))
    }

    func testLocalHelperInstallScriptsUseFixedPrivilegedPathsAndRollback() throws {
        let installScript = try String(
            contentsOf: projectRoot().appendingPathComponent("scripts/install-local-touchid-helper.sh"),
            encoding: .utf8
        )
        let uninstallScript = try String(
            contentsOf: projectRoot().appendingPathComponent("scripts/uninstall-local-touchid-helper.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(installScript.contains("HELPER_LABEL=\"com.local.RoamVibing.PrivilegedHelper\""))
        XCTAssertTrue(installScript.contains("APP_PATH=\"/Applications/RoamVibing.app\""))
        XCTAssertFalse(installScript.contains("APP_PATH=\"${1:-/Applications/RoamVibing.app}\""))
        XCTAssertTrue(installScript.contains("TARGET_HELPER=\"/Library/PrivilegedHelperTools/$HELPER_EXECUTABLE_NAME\""))
        XCTAssertTrue(installScript.contains("TARGET_PLIST=\"/Library/LaunchDaemons/$HELPER_LABEL.plist\""))
        XCTAssertTrue(installScript.contains("codesign --verify --deep --strict \"$APP_PATH\""))
        XCTAssertTrue(installScript.contains("codesign --verify --strict \"$BUNDLED_HELPER\""))
        XCTAssertTrue(installScript.contains("BUNDLED_HELPER=\"$1\""))
        XCTAssertTrue(installScript.contains("do shell script command with administrator privileges"))
        XCTAssertTrue(installScript.contains("/bin/launchctl bootstrap system \"$TARGET_PLIST\""))
        XCTAssertTrue(installScript.contains("defaults write com.local.RoamVibing UsePrivilegedHelper -bool true"))
        XCTAssertFalse(installScript.contains("curl"))
        XCTAssertFalse(installScript.contains("URLSession"))

        XCTAssertTrue(uninstallScript.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertTrue(uninstallScript.contains("/bin/launchctl bootout system/$HELPER_LABEL"))
        XCTAssertTrue(uninstallScript.contains("/bin/rm -f \"$TARGET_HELPER\" \"$TARGET_PLIST\""))
        XCTAssertTrue(uninstallScript.contains("defaults write com.local.RoamVibing UsePrivilegedHelper -bool false"))
        XCTAssertFalse(uninstallScript.contains("curl"))
        XCTAssertFalse(uninstallScript.contains("URLSession"))
    }

    func testDocsExplainPrivilegedHelperSecurityAndRollback() throws {
        let readme = try String(contentsOf: projectRoot().appendingPathComponent("README.md"), encoding: .utf8)
        let helperDoc = try String(contentsOf: projectRoot().appendingPathComponent("docs/privileged-helper-security.md"), encoding: .utf8)

        XCTAssertFalse(readme.contains("## Touch ID Helper"))
        XCTAssertTrue(readme.contains("## Security & Permissions"))
        XCTAssertTrue(readme.contains("administrator approval, Touch ID, or your Mac password"))
        XCTAssertTrue(readme.contains("does not include network client/server code"))
        XCTAssertTrue(readme.contains("docs/privileged-helper-security.md"))
        XCTAssertTrue(helperDoc.contains("The helper accepts only enable or disable"))
        XCTAssertTrue(helperDoc.contains("No shell"))
        XCTAssertTrue(helperDoc.contains("Rollback"))
        XCTAssertTrue(helperDoc.contains("ROAMVIBING_ENABLE_PRIVILEGED_HELPER=1"))
        XCTAssertTrue(helperDoc.contains("ROAMVIBING_NOTARY_KEYCHAIN_PROFILE"))
        XCTAssertTrue(helperDoc.contains("ROAMVIBING_SKIP_NOTARIZATION=1"))
        XCTAssertTrue(helperDoc.contains("Local-only helper testing"))
        XCTAssertTrue(helperDoc.contains("scripts/install-local-touchid-helper.sh"))
        XCTAssertTrue(helperDoc.contains("scripts/uninstall-local-touchid-helper.sh"))
        XCTAssertTrue(helperDoc.contains("notarized and stapled"))
        XCTAssertTrue(helperDoc.contains("disables Closed-Lid Mode before unregistering"))
    }

    private func allSwiftSource(under directory: URL) throws -> String {
        let fileManager = FileManager.default
        let files = try fileManager
            .subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }

        return try files
            .map { file in
                try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            }
            .joined(separator: "\n")
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func helperEnabledIfBlocks(in script: String) -> [String] {
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [String] = []

        for index in lines.indices where lines[index].contains("if [[ \"$ENABLE_PRIVILEGED_HELPER\" == \"1\" ]]; then") {
            var depth = 0
            var blockLines: [String] = []

            for line in lines[index...] {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)

                if trimmedLine.hasPrefix("if [[") {
                    depth += 1
                }

                blockLines.append(line)

                if trimmedLine == "fi" {
                    depth -= 1
                    if depth == 0 {
                        blocks.append(blockLines.joined(separator: "\n"))
                        break
                    }
                }
            }
        }

        return blocks
    }
}

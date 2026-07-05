import XCTest

final class MenuPresentationTests: XCTestCase {
    func testMenuKeepsPrimaryControlsAndMovesAdvancedControlsIntoSettings() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")
        let menuRange = try XCTUnwrap(source.range(of: "private func rebuildMenu()"))
        let nextMethodRange = try XCTUnwrap(source[menuRange.upperBound...].range(of: "private func makeClosedLidPowerManager()"))
        let menuSource = String(source[menuRange.lowerBound..<nextMethodRange.lowerBound])
        let settingsRange = try XCTUnwrap(source.range(of: "@objc private func showSettings()"))
        let nextSettingsMethodRange = try XCTUnwrap(source[settingsRange.upperBound...].range(of: "@objc private func"))
        let settingsSource = String(source[settingsRange.lowerBound..<nextSettingsMethodRange.lowerBound])

        XCTAssertTrue(source.contains("normalItem.state = session.state == .running(.normal) ? .on : .off"))
        XCTAssertTrue(source.contains("closedLidItem.state = session.state == .running(.closedLid) ? .on : .off"))
        XCTAssertTrue(menuSource.contains("title: normalToggleTitle"))
        XCTAssertTrue(menuSource.contains("title: closedLidToggleTitle"))
        XCTAssertTrue(menuSource.contains("title: \"Stop RoamVibing Session\""))
        XCTAssertTrue(menuSource.contains("title: \"Settings\""))
        XCTAssertTrue(menuSource.contains("action: #selector(showSettings)"))
        XCTAssertFalse(menuSource.contains("title: batterySafetyMenuTitle"))
        XCTAssertFalse(menuSource.contains("title: instantActivityLockMenuTitle"))
        XCTAssertFalse(menuSource.contains("title: \"Disable Closed-Lid Bypass\""))
        XCTAssertFalse(menuSource.contains("title: \"Install Touch ID Helper\""))
        XCTAssertFalse(menuSource.contains("title: usePrivilegedHelperMenuTitle"))
        XCTAssertFalse(menuSource.contains("title: \"Uninstall Touch ID Helper\""))

        XCTAssertTrue(settingsSource.contains("Battery Safety"))
        XCTAssertTrue(settingsSource.contains("Thermal Safety"))
        XCTAssertTrue(settingsSource.contains("Instant Lock on Activity"))
        XCTAssertTrue(settingsSource.contains("Mute on Lid Close"))
        XCTAssertTrue(settingsSource.contains("Emergency Reset"))
        XCTAssertTrue(settingsSource.contains("Reset Closed-Lid Bypass"))
        XCTAssertTrue(settingsSource.contains("Install Touch ID Helper"))
        XCTAssertTrue(settingsSource.contains("Use Touch ID Helper"))
        XCTAssertTrue(settingsSource.contains("Uninstall Touch ID Helper"))
    }

    func testSettingsIncludesPrivilegedHelperControlsWithClearCopy() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("Install Touch ID Helper"))
        XCTAssertTrue(source.contains("Use Touch ID Helper"))
        XCTAssertTrue(source.contains("Uninstall Touch ID Helper"))
        XCTAssertTrue(source.contains("Touch ID Helper: Not Installed"))
        XCTAssertTrue(source.contains("Touch ID Helper: Requires Approval"))
        XCTAssertTrue(source.contains("Touch ID Helper: Installed, in use"))
        XCTAssertTrue(source.contains("Touch ID Helper: Installed, not in use"))
        XCTAssertTrue(source.contains("helperCheckbox.isEnabled = helperStatus == .enabled && session.state == .stopped"))
        XCTAssertTrue(source.contains("installHelperButton.isEnabled = session.state == .stopped && helperStatus != .enabled"))
        XCTAssertTrue(source.contains("uninstallHelperButton.isEnabled = session.state == .stopped && helperStatus != .notRegistered && helperStatus != .notFound"))
        XCTAssertTrue(source.contains("Start Closed-Lid Mode with Touch ID or your Mac password after the helper is installed."))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("fingerprint"))
    }

    func testSettingsWindowUsesScrollableGroupedFormToAvoidTextOverlap() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("private enum SettingsDialog"))
        XCTAssertTrue(source.contains("static let contentWidth: CGFloat = 440"))
        XCTAssertTrue(source.contains("static let controlHeight: CGFloat = 28"))
        XCTAssertTrue(source.contains("private func runSettingsPanel(sections: [NSView]) -> NSApplication.ModalResponse"))
        XCTAssertTrue(source.contains("NSPanel(contentRect:"))
        XCTAssertTrue(source.contains("NSScrollView()"))
        XCTAssertTrue(source.contains("NSStackView(views: sections)"))
        XCTAssertTrue(source.contains("panel.contentView = rootView"))
        XCTAssertTrue(source.contains("scrollView.hasVerticalScroller = true"))
        XCTAssertTrue(source.contains("guard runSettingsPanel(sections:"))
        XCTAssertTrue(source.contains("title: \"Battery Safety\""))
        XCTAssertTrue(source.contains("description: \"Stops the RoamVibing session below your threshold while on battery so macOS can sleep normally.\""))
        XCTAssertTrue(source.contains("title: \"Thermal Safety\""))
        XCTAssertTrue(source.contains("description: \"Stops the RoamVibing session when macOS reports serious heat pressure so the Mac can cool down and sleep normally.\""))
        XCTAssertTrue(source.contains("title: \"Instant Lock on Activity\""))
        XCTAssertTrue(source.contains("description: \"Only applies to Closed-Lid Mode. After the safety delay, reopening the lid or using the keyboard or mouse locks the screen and turns RoamVibing off. Normal Awake does not use this lock.\""))
        XCTAssertTrue(source.contains("title: \"Mute on Lid Close\""))
        XCTAssertTrue(source.contains("description: \"Mutes supported active audio outputs when the lid closes during a RoamVibing session.\""))
        XCTAssertTrue(source.contains("title: \"Emergency Reset\""))
        XCTAssertTrue(source.contains("description: \"Emergency cleanup. Turns off the macOS closed-lid sleep bypass if it was left enabled outside a RoamVibing session.\""))
        XCTAssertTrue(source.contains("title: \"Touch ID Helper\""))
        XCTAssertTrue(source.contains("description: \"Use the installed privileged helper so Closed-Lid Mode can ask for Touch ID or your Mac password.\""))
        XCTAssertTrue(source.contains("settingsRow(title:"))
        XCTAssertTrue(source.contains("private func settingsSection(title: String, description: String, controls: [NSView]) -> NSView"))
        XCTAssertTrue(source.contains("NSTextField(wrappingLabelWithString: description)"))
        XCTAssertTrue(source.contains("descriptionLabel.preferredMaxLayoutWidth = SettingsDialog.contentWidth"))
        XCTAssertTrue(source.contains("descriptionLabel.maximumNumberOfLines = 0"))
        XCTAssertTrue(source.contains("translatesAutoresizingMaskIntoConstraints = false"))
        XCTAssertTrue(source.contains("NSLayoutConstraint.activate(["))
        XCTAssertFalse(source.contains("Battery Safety can stop a RoamVibing session at low battery. The idle delay gives you time"))
        XCTAssertFalse(source.contains("alert.accessoryView = makeSettingsAccessory"))
        XCTAssertFalse(source.contains("private func makeSettingsAccessory(controls: [NSView]) -> NSView"))
        XCTAssertFalse(source.contains("private func horizontalStack"))
    }

    func testSettingsWindowShowsAppLogoAndHasWorkingCancelController() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("private final class SettingsPanelController: NSObject, NSWindowDelegate"))
        XCTAssertTrue(source.contains("@objc func cancel(_ sender: Any?)"))
        XCTAssertTrue(source.contains("finish(with: .cancel)"))
        XCTAssertTrue(source.contains("panel?.close()"))
        XCTAssertTrue(source.contains("cancelButton.target = controller"))
        XCTAssertTrue(source.contains("cancelButton.action = #selector(SettingsPanelController.cancel(_:))"))
        XCTAssertTrue(source.contains("panel.delegate = controller"))
        XCTAssertTrue(source.contains("let logoView = NSImageView()"))
        XCTAssertTrue(source.contains("logoView.image = NSImage(named: \"RoamVibingIcon\") ?? NSApp.applicationIconImage"))
        XCTAssertTrue(source.contains("logoView.setAccessibilityLabel(\"RoamVibing logo\")"))
        XCTAssertTrue(source.contains("rootView.addSubview(logoView)"))
        XCTAssertTrue(source.contains("logoView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: SettingsDialog.panelPadding)"))
        XCTAssertFalse(source.contains("ModalActionTarget"))
        XCTAssertFalse(source.contains("SettingsPanelCloseDelegate"))
    }

    func testSettingsDialogsUseShortCheckboxLabels() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertEqual(source.components(separatedBy: "checkboxWithTitle: \"Enabled\"").count - 1, 4)
        XCTAssertFalse(source.contains("checkboxWithTitle: \"Lock screen when keyboard or mouse input is detected\""))
        XCTAssertFalse(source.contains("checkboxWithTitle: \"Allow sleep when battery is low\""))
    }

    func testSettingsDialogSavesAllPoliciesTogether() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("batterySafetySettings.policy = LowBatteryPolicy("))
        XCTAssertTrue(source.contains("thermalSafetySettings.policy = ThermalSafetyPolicy("))
        XCTAssertTrue(source.contains("instantActivityLockSettings.policy = InstantActivityLockPolicy("))
        XCTAssertTrue(source.contains("muteOnLidCloseSettings.policy = MuteOnLidClosePolicy("))
        XCTAssertTrue(source.contains("lowBatteryGuard.policy = batterySafetySettings.policy"))
        XCTAssertTrue(source.contains("thermalSafetyGuard.policy = thermalSafetySettings.policy"))
        XCTAssertTrue(source.contains("instantActivityLockGuard.policy = instantActivityLockSettings.policy"))
        XCTAssertTrue(source.contains("muteOnLidCloseGuard.policy = muteOnLidCloseSettings.policy"))
        XCTAssertTrue(source.contains("if helperCheckbox.isEnabled {"))
        XCTAssertTrue(source.contains("UserDefaults.standard.set(helperCheckbox.state == .on, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)"))
    }

    func testSettingsControlsExposeAccessibleNames() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("batteryCheckbox.setAccessibilityLabel(\"Enable Battery Safety\")"))
        XCTAssertTrue(source.contains("batteryPopup.setAccessibilityLabel(\"Battery threshold\")"))
        XCTAssertTrue(source.contains("thermalCheckbox.setAccessibilityLabel(\"Enable Thermal Safety\")"))
        XCTAssertTrue(source.contains("instantCheckbox.setAccessibilityLabel(\"Enable Instant Lock on Activity\")"))
        XCTAssertTrue(source.contains("instantCheckbox.setAccessibilityHelp(\"Only applies to Closed-Lid Mode. Normal Awake does not use this lock.\")"))
        XCTAssertTrue(source.contains("instantPopup.setAccessibilityLabel(\"Safety delay\")"))
        XCTAssertTrue(source.contains("instantPopup.setAccessibilityHelp(\"Choose the Closed-Lid Mode safety delay before activity can trigger an instant lock.\")"))
        XCTAssertTrue(source.contains("muteCheckbox.setAccessibilityLabel(\"Enable Mute on Lid Close\")"))
        XCTAssertTrue(source.contains("helperStatusLabel.setAccessibilityLabel(\"Touch ID Helper status\")"))
        XCTAssertTrue(source.contains("helperCheckbox.setAccessibilityLabel(\"Use Touch ID Helper\")"))
        XCTAssertTrue(source.contains("disableBypassButton.setAccessibilityLabel(\"Reset Closed-Lid Bypass\")"))
    }

    func testAlertsUseSeverityAppropriateStyles() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("private func showAlert(title: String, message: String, style: NSAlert.Style = .informational)"))
        XCTAssertTrue(source.contains("presentError(error, title: errorTitle)"))
        XCTAssertTrue(source.contains("style: .critical"))
        XCTAssertTrue(source.contains("title: \"Closed-Lid Mode Safety\","))
        XCTAssertTrue(source.contains("style: .warning"))
        XCTAssertTrue(source.contains("title: \"Battery Safety Blocked RoamVibing Session\","))
        XCTAssertTrue(source.contains("title: \"Battery Safety Stopped \\(Brand.appName)\","))
        XCTAssertTrue(source.contains("title: \"Thermal Safety Blocked RoamVibing Session\","))
        XCTAssertTrue(source.contains("title: \"Thermal Safety Stopped \\(Brand.appName)\","))
        XCTAssertTrue(source.contains("Thermal Safety uses macOS thermal pressure and turns RoamVibing off when the system reports serious heat pressure."))
        XCTAssertTrue(source.contains("It does not read raw CPU or GPU temperatures."))
    }

    func testMenuTitlesDoNotUseTrailingEllipsesAsGenericDecoration() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")
        let linesWithTrailingEllipses = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line -> String? in
                guard line.contains("...\"") else {
                    return nil
                }

                return "\(index + 1): \(line)"
            }

        XCTAssertTrue(
            linesWithTrailingEllipses.isEmpty,
            "Menu titles should avoid trailing ellipses unless the wording has a specific purpose: \(linesWithTrailingEllipses)"
        )
    }

    func testUserFacingSessionCopyUsesRoamVibingSessionName() throws {
        let source = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(source.contains("Stop RoamVibing Session"))
        XCTAssertTrue(source.contains("Could Not Stop RoamVibing Session"))
        XCTAssertTrue(source.contains("RoamVibing session"))
        XCTAssertFalse(source.contains("Stop Awake Session"))
        XCTAssertFalse(source.contains("Could Not Stop Awake Session"))
        XCTAssertFalse(source.contains("Awake Session"))
        XCTAssertFalse(source.contains("awake session"))
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

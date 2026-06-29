import XCTest
@testable import LidAwakeCore

final class PowerHelperTests: XCTestCase {
    func testCurrentAdministratorPowerManagerStillExistsAsFallback() throws {
        let package = try readText("Package.swift")
        let adminPowerManager = try readText("Sources/LidAwakeCore/AdminClosedLidPowerManager.swift")

        XCTAssertTrue(package.contains(".target("))
        XCTAssertTrue(package.contains("name: \"LidAwakeCore\""))
        XCTAssertTrue(adminPowerManager.contains("public final class AdminClosedLidPowerManager"))
        XCTAssertTrue(adminPowerManager.contains("/usr/bin/osascript"))
    }

    func testAppSelectsHelperOnlyThroughPowerManagerSelection() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("ClosedLidPowerManagerSelection.make()"))
        XCTAssertTrue(appDelegate.contains("closedLidPower: makeClosedLidPowerManager()"))
        XCTAssertTrue(appDelegate.contains("try session.stop(intent: .safety)"))
        XCTAssertTrue(appDelegate.contains("try self.session.stop(intent: .safety)"))
        XCTAssertTrue(appDelegate.contains("makeClosedLidPowerManager().setClosedLidBypassEnabled(false, intent: .safety)"))
        XCTAssertFalse(appDelegate.contains("closedLidPower: AdminClosedLidPowerManager()"))
        XCTAssertFalse(appDelegate.contains("AdminClosedLidPowerManager().setClosedLidBypassEnabled(false)"))
    }

    func testClosedLidPowerActionsRunOffTheMenuTrackingThread() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("private let powerOperationQueue = DispatchQueue(label: \"com.local.RoamVibing.power-operation\")"))
        XCTAssertTrue(appDelegate.contains("private var activePowerOperation: PowerOperation?"))
        XCTAssertTrue(appDelegate.contains("private func beginPowerOperation("))
        XCTAssertTrue(appDelegate.contains("powerOperationQueue.async"))
        XCTAssertTrue(appDelegate.contains("DispatchQueue.main.async"))
        XCTAssertTrue(appDelegate.contains("normalItem.isEnabled = activePowerOperation == nil"))
        XCTAssertTrue(appDelegate.contains("closedLidItem.isEnabled = activePowerOperation == nil"))
        XCTAssertTrue(appDelegate.contains("settingsItem.isEnabled = activePowerOperation == nil && activeHelperOperation == nil"))
        XCTAssertTrue(appDelegate.contains("disableBypassButton.isEnabled = true"))
        XCTAssertTrue(appDelegate.contains("quitItem.isEnabled = activePowerOperation == nil"))
    }

    func testPrivilegedHelperActionsRunOffTheMenuTrackingThread() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("private let helperOperationQueue = DispatchQueue(label: \"com.local.RoamVibing.helper-operation\")"))
        XCTAssertTrue(appDelegate.contains("private var activeHelperOperation: HelperOperation?"))
        XCTAssertTrue(appDelegate.contains("private func beginHelperOperation("))
        XCTAssertTrue(appDelegate.contains("helperOperationQueue.async"))
        XCTAssertTrue(appDelegate.contains("DispatchQueue.main.async"))
        XCTAssertTrue(appDelegate.contains("beginHelperOperation(.installing, errorTitle: \"Could Not Install Touch ID Helper\")"))
        XCTAssertTrue(appDelegate.contains("beginHelperOperation(.uninstalling, errorTitle: \"Could Not Uninstall Touch ID Helper\")"))
        XCTAssertTrue(appDelegate.contains("installHelperButton.isEnabled = session.state == .stopped && helperStatus != .enabled"))
        XCTAssertTrue(appDelegate.contains("helperCheckbox.isEnabled = helperStatus == .enabled && session.state == .stopped"))
        XCTAssertTrue(appDelegate.contains("uninstallHelperButton.isEnabled = session.state == .stopped && helperStatus != .notRegistered && helperStatus != .notFound"))
    }

    func testPrivilegedHelperCompletionUpdatesPreferencesAndRuntimeOnMainQueue() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")
        let helperOperationRange = try XCTUnwrap(appDelegate.range(of: "private func beginHelperOperation("))
        let helperOperationSource = appDelegate[helperOperationRange.lowerBound...]
        XCTAssertTrue(helperOperationSource.contains("DispatchQueue.main.async"))

        let uninstallOperationRange = try XCTUnwrap(appDelegate.range(of: "beginHelperOperation(.uninstalling, errorTitle: \"Could Not Uninstall Touch ID Helper\")"))
        let uninstallOperationSource = appDelegate[uninstallOperationRange.lowerBound..<helperOperationRange.lowerBound]
        let userDefaultsRange = try XCTUnwrap(uninstallOperationSource.range(of: "UserDefaults.standard.set(false, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)"))
        let rebuildRuntimeRange = try XCTUnwrap(uninstallOperationSource.range(of: "self.rebuildRuntimeObjects()"))

        XCTAssertLessThan(userDefaultsRange.lowerBound, rebuildRuntimeRange.lowerBound)
    }

    func testQuitIsCancelledWhilePowerOperationIsActive() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")
        let terminationRange = try XCTUnwrap(appDelegate.range(of: "func applicationShouldTerminate"))
        let postTerminationSource = appDelegate[terminationRange.lowerBound...]
        let guardRange = try XCTUnwrap(postTerminationSource.range(of: "guard activePowerOperation == nil, activeHelperOperation == nil else"))
        let sessionStateRange = try XCTUnwrap(postTerminationSource.range(of: "guard session.state != .stopped else"))

        XCTAssertLessThan(guardRange.lowerBound, sessionStateRange.lowerBound)
        guard guardRange.lowerBound < sessionStateRange.lowerBound else {
            return
        }

        let activeOperationGuard = postTerminationSource[guardRange.lowerBound..<sessionStateRange.lowerBound]
        XCTAssertTrue(activeOperationGuard.contains("rebuildMenu()"))
        XCTAssertTrue(activeOperationGuard.contains("return .terminateCancel"))
    }

    func testTerminateInvalidatesSafetyTimersOnlyAfterSafetyStopCanThrow() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")
        let terminationRange = try XCTUnwrap(appDelegate.range(of: "func applicationShouldTerminate"))
        let postTerminationSource = appDelegate[terminationRange.lowerBound...]
        let stopRange = try XCTUnwrap(postTerminationSource.range(of: "try session.stop(intent: .safety)"))
        let batteryTimerRange = try XCTUnwrap(postTerminationSource.range(of: "batterySafetyTimer?.invalidate()"))
        let instantLockTimerRange = try XCTUnwrap(postTerminationSource.range(of: "instantActivityLockTimer?.invalidate()"))

        XCTAssertLessThan(stopRange.lowerBound, batteryTimerRange.lowerBound)
        XCTAssertLessThan(stopRange.lowerBound, instantLockTimerRange.lowerBound)
    }

    func testClosedLidPowerManagerSelectionHasOneAppDelegateSeam() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("private func makeClosedLidPowerManager() -> ClosedLidPowerManaging"))
        XCTAssertTrue(appDelegate.contains("private func makeSession() -> AwakeSession"))
        XCTAssertTrue(appDelegate.contains("private func rebuildRuntimeObjects()"))
        XCTAssertTrue(appDelegate.contains("guard activePowerOperation == nil, activeHelperOperation == nil, session.state == .stopped else"))
        XCTAssertTrue(appDelegate.contains("closedLidPower: makeClosedLidPowerManager()"))
        XCTAssertTrue(appDelegate.contains("try self.makeClosedLidPowerManager().setClosedLidBypassEnabled(false, intent: .safety)"))
    }

    func testStartRefreshesRuntimeObjectsBeforeUsingStoredPowerManager() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")
        let startRange = try XCTUnwrap(appDelegate.range(of: "private func start(mode: SessionMode)"))
        let startSource = appDelegate[startRange.lowerBound...]
        let refreshRange = try XCTUnwrap(startSource.range(of: "rebuildRuntimeObjects()"))
        let needsPowerOperationRange = try XCTUnwrap(startSource.range(of: "let needsPowerOperation = mode == .closedLid"))
        let sessionStartRange = try XCTUnwrap(startSource.range(of: "try self.session.start(mode: mode)"))

        XCTAssertLessThan(refreshRange.lowerBound, needsPowerOperationRange.lowerBound)
        XCTAssertLessThan(refreshRange.lowerBound, sessionStartRange.lowerBound)
    }

    func testAppDelegateInstallsAndUninstallsHelperThroughInstaller() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("PrivilegedHelperInstaller().install()"))
        XCTAssertTrue(appDelegate.contains("PrivilegedHelperInstaller().uninstall()"))
    }

    func testMainProvidesOneShotHelperInstallAndRollbackCommands() throws {
        let main = try readText("Sources/LidAwake/main.swift")

        XCTAssertTrue(main.contains("--install-touch-id-helper-and-exit"))
        XCTAssertTrue(main.contains("--use-touch-id-helper-and-exit"))
        XCTAssertTrue(main.contains("--diagnose-touch-id-helper-and-exit"))
        XCTAssertTrue(main.contains("--uninstall-touch-id-helper-and-exit"))
        XCTAssertTrue(main.contains("PrivilegedHelperInstaller().install()"))
        XCTAssertTrue(main.contains("PrivilegedHelperInstaller().uninstall()"))
        XCTAssertTrue(main.contains("UserDefaults.standard.set(true, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)"))
        XCTAssertTrue(main.contains("UserDefaults.standard.set(false, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)"))
        XCTAssertTrue(main.contains("ClosedLidPowerManagerSelection.shouldUsePrivilegedHelper(helperStatus: status)"))
        XCTAssertTrue(main.contains("closedLidPowerManager=\\(managerName)"))
    }

    func testAppDelegateWiresPrivilegedHelperRuntimePreference() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("ClosedLidPowerManagerSelection.usePrivilegedHelperKey"))
        XCTAssertTrue(appDelegate.contains("UserDefaults.standard.set"))
        XCTAssertTrue(appDelegate.contains("rebuildRuntimeObjects()"))
    }

    func testAppDelegateRebuildsRuntimeGuardsWithoutImplicitlyUnwrappedState() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("lowBatteryGuard = LowBatteryGuard("))
        XCTAssertTrue(appDelegate.contains("instantActivityLockGuard = InstantActivityLockGuard("))
        XCTAssertTrue(appDelegate.contains("muteOnLidCloseGuard = makeMuteOnLidCloseGuard()"))
        XCTAssertTrue(appDelegate.contains("private lazy var lowBatteryGuard = makeLowBatteryGuard()"))
        XCTAssertTrue(appDelegate.contains("private lazy var instantActivityLockGuard = makeInstantActivityLockGuard()"))
        XCTAssertTrue(appDelegate.contains("private lazy var muteOnLidCloseGuard = makeMuteOnLidCloseGuard()"))
        XCTAssertFalse(appDelegate.contains("LowBatteryGuard!"))
        XCTAssertFalse(appDelegate.contains("InstantActivityLockGuard!"))
        XCTAssertFalse(appDelegate.contains("MuteOnLidCloseGuard!"))
        XCTAssertFalse(appDelegate.contains("rebuildSession()"))
    }

    func testClosedLidCopyAllowsHelperAuthorizationPath() throws {
        let appDelegate = try readText("Sources/LidAwake/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("This may ask for administrator approval or use the installed privileged helper to run:"))
        XCTAssertFalse(appDelegate.contains("This will ask for an administrator password and run:"))
    }

    func testBuildScriptDoesNotPackageOrSignEmbeddedPowerHelper() throws {
        let script = try readText("scripts/build-app.sh")

        XCTAssertFalse(script.contains("RoamVibingPowerHelper"))
        XCTAssertFalse(script.contains("HELPER_APP"))
        XCTAssertFalse(script.contains("LoginItems"))
        XCTAssertFalse(script.contains("--entitlements \"$ENTITLEMENTS_FILE\""))
        XCTAssertTrue(script.contains("codesign --force --sign - \"$STAGING_APP\""))
    }

    func testLaunchDaemonPlistExposesOnlyHelperMachService() throws {
        let plistURL = projectRoot()
            .appendingPathComponent("Resources")
            .appendingPathComponent("LaunchDaemons")
            .appendingPathComponent("com.local.RoamVibing.PrivilegedHelper.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["Label"] as? String, "com.local.RoamVibing.PrivilegedHelper")
        XCTAssertEqual(
            plist["BundleProgram"] as? String,
            "Contents/Library/LaunchDaemons/RoamVibingPrivilegedHelper"
        )
        XCTAssertEqual(
            plist["MachServices"] as? [String: Bool],
            ["com.local.RoamVibing.PrivilegedHelper": true]
        )
        XCTAssertNil(plist["ProgramArguments"])
        XCTAssertNil(plist["Sockets"])
        XCTAssertNil(plist["KeepAlive"])
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

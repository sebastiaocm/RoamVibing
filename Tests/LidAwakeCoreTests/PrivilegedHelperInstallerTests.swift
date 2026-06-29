import Foundation
import XCTest
@testable import LidAwakeCore

final class PrivilegedHelperInstallerTests: XCTestCase {
    func testForwardsEveryServiceStatus() throws {
        for status in [PrivilegedHelperStatus.notRegistered, .enabled, .requiresApproval, .notFound] {
            let service = RecordingPrivilegedService(status: status)
            let installer = makeInstaller(service: service)

            XCTAssertEqual(installer.status, status)
        }
    }

    func testManualLaunchDaemonFallbackReportsEnabledWhenServiceIsNotEnabled() throws {
        for status in [PrivilegedHelperStatus.notRegistered, .requiresApproval, .notFound] {
            let service = RecordingPrivilegedService(status: status)
            let installer = makeInstaller(
                service: service,
                manualLaunchDaemonChecker: RecordingManualLaunchDaemonStatusChecker(isInstalled: true)
            )

            XCTAssertEqual(installer.status, .enabled)
        }
    }

    func testManualLaunchDaemonFallbackDoesNotOverrideEnabledService() throws {
        let service = RecordingPrivilegedService(status: .enabled)
        let installer = makeInstaller(
            service: service,
            manualLaunchDaemonChecker: RecordingManualLaunchDaemonStatusChecker(isInstalled: false)
        )

        XCTAssertEqual(installer.status, .enabled)
    }

    func testFileSystemManualLaunchDaemonCheckerRequiresPlistAndExecutableHelper() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let launchDaemonPath = temporaryDirectory.appendingPathComponent("helper.plist").path
        let helperPath = temporaryDirectory.appendingPathComponent("RoamVibingPrivilegedHelper").path
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let checker = FileSystemManualLaunchDaemonStatusChecker(
            fileManager: .default,
            launchDaemonPath: launchDaemonPath,
            helperExecutablePath: helperPath
        )

        XCTAssertFalse(checker.isInstalled)

        FileManager.default.createFile(atPath: launchDaemonPath, contents: Data())
        XCTAssertFalse(checker.isInstalled)

        FileManager.default.createFile(atPath: helperPath, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperPath)
        XCTAssertTrue(checker.isInstalled)
    }

    func testRegisterCallsService() throws {
        let service = RecordingPrivilegedService()
        let installer = makeInstaller(service: service)

        try installer.install()

        XCTAssertEqual(service.events, [.register])
    }

    func testRejectsBundleOutsideApplications() {
        let service = RecordingPrivilegedService()
        let installer = makeInstaller(
            service: service,
            bundleLocation: RecordingBundleLocation(path: "/Users/me/RoamVibing.app")
        )

        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? PrivilegedHelperInstallerError, .appMustLiveInApplications)
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("/Applications"))
        }

        XCTAssertEqual(service.events, [])
    }

    func testRejectsPathTraversalOutsideApplications() {
        let service = RecordingPrivilegedService()
        let installer = makeInstaller(
            service: service,
            bundleLocation: RecordingBundleLocation(path: "/Applications/../tmp/RoamVibing.app")
        )

        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? PrivilegedHelperInstallerError, .appMustLiveInApplications)
        }

        XCTAssertEqual(service.events, [])
    }

    func testRejectsSymlinkInsideApplicationsWhenTargetOutsideApplicationsUsingInjectableApplicationsDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let applicationsDirectory = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let outsideDirectory = temporaryDirectory.appendingPathComponent("outside", isDirectory: true)
        let outsideBundle = outsideDirectory.appendingPathComponent("RoamVibing.app", isDirectory: true)
        let symlinkBundle = applicationsDirectory.appendingPathComponent("RoamVibing.app")

        try FileManager.default.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideBundle, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkBundle, withDestinationURL: outsideBundle)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = RecordingPrivilegedService()
        let installer = makeInstaller(
            service: service,
            bundleLocation: RecordingBundleLocation(url: symlinkBundle),
            applicationsDirectory: applicationsDirectory
        )

        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? PrivilegedHelperInstallerError, .appMustLiveInApplications)
        }

        XCTAssertEqual(service.events, [])
    }

    func testEnabledUninstallDisablesClosedLidBypassBeforeUnregistering() throws {
        let eventLog = UninstallEventLog()
        let service = RecordingPrivilegedService(status: .enabled, eventLog: eventLog)
        let disabler = RecordingUninstallSafetyDisabler(eventLog: eventLog)
        let installer = makeInstaller(service: service, closedLidDisabler: disabler)

        try installer.uninstall()

        XCTAssertEqual(eventLog.events, ["disable", "unregister"])
    }

    func testRequiresApprovalUninstallSkipsClosedLidBypassDisableAndUnregisters() throws {
        let eventLog = UninstallEventLog()
        let service = RecordingPrivilegedService(status: .requiresApproval, eventLog: eventLog)
        let disabler = RecordingUninstallSafetyDisabler(error: InstallerTestError.expected, eventLog: eventLog)
        let installer = makeInstaller(service: service, closedLidDisabler: disabler)

        try installer.uninstall()

        XCTAssertEqual(eventLog.events, ["unregister"])
    }

    func testEnabledUninstallDoesNotUnregisterWhenClosedLidBypassDisableFails() {
        let eventLog = UninstallEventLog()
        let service = RecordingPrivilegedService(status: .enabled, eventLog: eventLog)
        let disabler = RecordingUninstallSafetyDisabler(error: InstallerTestError.expected, eventLog: eventLog)
        let installer = makeInstaller(service: service, closedLidDisabler: disabler)

        XCTAssertThrowsError(try installer.uninstall()) { error in
            XCTAssertEqual(error as? InstallerTestError, .expected)
        }

        XCTAssertEqual(eventLog.events, ["disable"])
        XCTAssertEqual(service.events, [])
    }

    func testSelectionDefaultsToAdministratorPromptWhenHelperIsUnavailable() {
        let suiteName = "PrivilegedHelperInstallerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ClosedLidPowerManagerSelection.make(userDefaults: defaults, helperStatus: .notRegistered)

        XCTAssertTrue(manager is AdminClosedLidPowerManager)
    }

    func testSelectionDefaultsToHelperWhenHelperIsEnabled() {
        let suiteName = "PrivilegedHelperInstallerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ClosedLidPowerManagerSelection.make(userDefaults: defaults, helperStatus: .enabled)

        XCTAssertTrue(manager is PrivilegedHelperClosedLidPowerManager)
        XCTAssertTrue(ClosedLidPowerManagerSelection.shouldUsePrivilegedHelper(userDefaults: defaults, helperStatus: .enabled))
    }

    func testSelectionRespectsExplicitHelperOptOut() {
        let suiteName = "PrivilegedHelperInstallerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)

        let manager = ClosedLidPowerManagerSelection.make(userDefaults: defaults, helperStatus: .enabled)

        XCTAssertTrue(manager is AdminClosedLidPowerManager)
        XCTAssertFalse(ClosedLidPowerManagerSelection.shouldUsePrivilegedHelper(userDefaults: defaults, helperStatus: .enabled))
    }

    func testSelectionUsesHelperOnlyWhenPreferenceIsOnAndHelperEnabled() {
        let suiteName = "PrivilegedHelperInstallerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)

        let manager = ClosedLidPowerManagerSelection.make(userDefaults: defaults, helperStatus: .enabled)

        XCTAssertTrue(manager is PrivilegedHelperClosedLidPowerManager)
    }

    func testSelectionFallsBackToAdministratorWhenPreferredHelperIsUnavailable() {
        let suiteName = "PrivilegedHelperInstallerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)

        for status in [PrivilegedHelperStatus.notRegistered, .requiresApproval, .notFound] {
            let manager = ClosedLidPowerManagerSelection.make(userDefaults: defaults, helperStatus: status)

            XCTAssertTrue(manager is AdminClosedLidPowerManager, "Expected administrator fallback for \(status)")
        }
    }

    private func makeInstaller(
        service: RecordingPrivilegedService = RecordingPrivilegedService(),
        bundleLocation: RecordingBundleLocation = RecordingBundleLocation(path: "/Applications/RoamVibing.app"),
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        closedLidDisabler: RecordingUninstallSafetyDisabler = RecordingUninstallSafetyDisabler(),
        manualLaunchDaemonChecker: ManualLaunchDaemonStatusChecking = NeverInstalledManualLaunchDaemonStatusChecker()
    ) -> PrivilegedHelperInstaller {
        PrivilegedHelperInstaller(
            service: service,
            bundleLocation: bundleLocation,
            applicationsDirectory: applicationsDirectory,
            closedLidDisabler: closedLidDisabler,
            manualLaunchDaemonChecker: manualLaunchDaemonChecker
        )
    }
}

private final class RecordingPrivilegedService: PrivilegedServiceManaging {
    enum Event: Equatable {
        case register
        case unregister
    }

    private let eventLog: UninstallEventLog?
    let status: PrivilegedHelperStatus
    private(set) var events: [Event] = []

    init(status: PrivilegedHelperStatus = .notRegistered, eventLog: UninstallEventLog? = nil) {
        self.status = status
        self.eventLog = eventLog
    }

    func register() throws {
        events.append(.register)
    }

    func unregister() throws {
        events.append(.unregister)
        eventLog?.events.append("unregister")
    }
}

private final class UninstallEventLog {
    var events: [String] = []
}

private final class RecordingUninstallSafetyDisabler: PrivilegedHelperUninstallSafetyDisabling {
    private let error: Error?
    private let eventLog: UninstallEventLog?

    init(error: Error? = nil, eventLog: UninstallEventLog? = nil) {
        self.error = error
        self.eventLog = eventLog
    }

    func disableClosedLidBypassBeforeUninstall() throws {
        eventLog?.events.append("disable")
        if let error {
            throw error
        }
    }
}

private struct RecordingManualLaunchDaemonStatusChecker: ManualLaunchDaemonStatusChecking {
    let isInstalled: Bool
}

private struct RecordingBundleLocation: ApplicationBundleLocationChecking {
    let bundleURL: URL

    init(path: String) {
        bundleURL = URL(fileURLWithPath: path)
    }

    init(url: URL) {
        bundleURL = url
    }
}

private enum InstallerTestError: Error, Equatable {
    case expected
}

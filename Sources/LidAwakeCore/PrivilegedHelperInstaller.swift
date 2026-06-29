import Foundation
import ServiceManagement
import PrivilegedHelperProtocol

public enum PrivilegedHelperStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public protocol PrivilegedServiceManaging: AnyObject {
    var status: PrivilegedHelperStatus { get }

    func register() throws
    func unregister() throws
}

public protocol PrivilegedHelperStatusChecking {
    var status: PrivilegedHelperStatus { get }
}

public protocol PrivilegedHelperUninstallSafetyDisabling: AnyObject {
    func disableClosedLidBypassBeforeUninstall() throws
}

public protocol ApplicationBundleLocationChecking {
    var bundleURL: URL { get }
}

public protocol ManualLaunchDaemonStatusChecking {
    var isInstalled: Bool { get }
}

extension Bundle: ApplicationBundleLocationChecking {}

public enum PrivilegedHelperInstallerError: LocalizedError, Equatable {
    case appMustLiveInApplications

    public var errorDescription: String? {
        switch self {
        case .appMustLiveInApplications:
            return "Install RoamVibing in /Applications before installing the privileged helper."
        }
    }
}

public final class PrivilegedHelperInstaller: PrivilegedHelperStatusChecking {
    private let service: PrivilegedServiceManaging
    private let bundleLocation: ApplicationBundleLocationChecking
    private let applicationsDirectory: URL
    private let closedLidDisabler: PrivilegedHelperUninstallSafetyDisabling
    private let manualLaunchDaemonChecker: ManualLaunchDaemonStatusChecking

    public var status: PrivilegedHelperStatus {
        let serviceStatus = service.status
        guard serviceStatus != .enabled, manualLaunchDaemonChecker.isInstalled else {
            return serviceStatus
        }

        return .enabled
    }

    public convenience init() {
        self.init(
            service: SMAppPrivilegedService(),
            bundleLocation: Bundle.main,
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
            closedLidDisabler: PrivilegedHelperUninstallSafetyDisabler(),
            manualLaunchDaemonChecker: FileSystemManualLaunchDaemonStatusChecker()
        )
    }

    public init(
        service: PrivilegedServiceManaging,
        bundleLocation: ApplicationBundleLocationChecking,
        applicationsDirectory: URL,
        closedLidDisabler: PrivilegedHelperUninstallSafetyDisabling,
        manualLaunchDaemonChecker: ManualLaunchDaemonStatusChecking = NeverInstalledManualLaunchDaemonStatusChecker()
    ) {
        self.service = service
        self.bundleLocation = bundleLocation
        self.applicationsDirectory = applicationsDirectory
        self.closedLidDisabler = closedLidDisabler
        self.manualLaunchDaemonChecker = manualLaunchDaemonChecker
    }

    public func install() throws {
        guard bundleIsInsideApplications() else {
            throw PrivilegedHelperInstallerError.appMustLiveInApplications
        }

        try service.register()
    }

    public func uninstall() throws {
        if service.status == .enabled {
            try closedLidDisabler.disableClosedLidBypassBeforeUninstall()
        }
        try service.unregister()
    }

    private func bundleIsInsideApplications() -> Bool {
        let canonicalBundleURL = bundleLocation.bundleURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalApplicationsURL = applicationsDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let bundleComponents = canonicalBundleURL.pathComponents
        let applicationsComponents = canonicalApplicationsURL.pathComponents

        guard bundleComponents.count > applicationsComponents.count else {
            return false
        }

        return Array(bundleComponents.prefix(applicationsComponents.count)) == applicationsComponents
    }
}

public final class FileSystemManualLaunchDaemonStatusChecker: ManualLaunchDaemonStatusChecking {
    private let fileManager: FileManager
    private let launchDaemonPath: String
    private let helperExecutablePath: String

    public convenience init() {
        self.init(
            fileManager: .default,
            launchDaemonPath: "/Library/LaunchDaemons/\(PrivilegedHelperConstants.launchDaemonPlistName)",
            helperExecutablePath: "/Library/PrivilegedHelperTools/\(PrivilegedHelperConstants.helperExecutableName)"
        )
    }

    init(fileManager: FileManager, launchDaemonPath: String, helperExecutablePath: String) {
        self.fileManager = fileManager
        self.launchDaemonPath = launchDaemonPath
        self.helperExecutablePath = helperExecutablePath
    }

    public var isInstalled: Bool {
        fileManager.fileExists(atPath: launchDaemonPath)
            && fileManager.isExecutableFile(atPath: helperExecutablePath)
    }
}

public struct NeverInstalledManualLaunchDaemonStatusChecker: ManualLaunchDaemonStatusChecking {
    public init() {}

    public var isInstalled: Bool {
        false
    }
}

public final class PrivilegedHelperUninstallSafetyDisabler: PrivilegedHelperUninstallSafetyDisabling {
    private let powerManager: ClosedLidPowerManaging

    public init(powerManager: ClosedLidPowerManaging = PrivilegedHelperClosedLidPowerManager()) {
        self.powerManager = powerManager
    }

    public func disableClosedLidBypassBeforeUninstall() throws {
        try powerManager.setClosedLidBypassEnabled(false, intent: .safety)
    }
}

public final class SMAppPrivilegedService: PrivilegedServiceManaging {
    private let service: SMAppService

    public var status: PrivilegedHelperStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    public convenience init() {
        self.init(
            service: .daemon(plistName: PrivilegedHelperConstants.launchDaemonPlistName)
        )
    }

    init(service: SMAppService) {
        self.service = service
    }

    public func register() throws {
        try service.register()
    }

    public func unregister() throws {
        try service.unregister()
    }
}

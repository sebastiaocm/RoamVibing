import AppKit
import LidAwakeCore

private enum OneShotCommand {
    static func runIfRequested(arguments: [String]) -> Bool {
        if arguments.contains("--install-touch-id-helper-and-exit") {
            run("Install Touch ID Helper") {
                try PrivilegedHelperInstaller().install()
                UserDefaults.standard.set(true, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)
            }
        }

        if arguments.contains("--use-touch-id-helper-and-exit") {
            UserDefaults.standard.set(true, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)
            return true
        }

        if arguments.contains("--diagnose-touch-id-helper-and-exit") {
            diagnoseTouchIDHelper()
            return true
        }

        if arguments.contains("--uninstall-touch-id-helper-and-exit") {
            run("Uninstall Touch ID Helper") {
                try PrivilegedHelperInstaller().uninstall()
                UserDefaults.standard.set(false, forKey: ClosedLidPowerManagerSelection.usePrivilegedHelperKey)
            }
        }

        return false
    }

    private static func diagnoseTouchIDHelper() {
        let status = PrivilegedHelperInstaller().status
        let manager = ClosedLidPowerManagerSelection.make()
        let shouldUseHelper = ClosedLidPowerManagerSelection.shouldUsePrivilegedHelper(helperStatus: status)
        let managerName = manager is PrivilegedHelperClosedLidPowerManager
            ? "PrivilegedHelperClosedLidPowerManager"
            : "AdminClosedLidPowerManager"
        let output = """
        helperStatus=\(statusName(status))
        effectiveUsePrivilegedHelper=\(shouldUseHelper)
        closedLidPowerManager=\(managerName)

        """
        FileHandle.standardOutput.write(Data(output.utf8))
    }

    private static func statusName(_ status: PrivilegedHelperStatus) -> String {
        switch status {
        case .notRegistered:
            return "notRegistered"
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requiresApproval"
        case .notFound:
            return "notFound"
        }
    }

    private static func run(_ name: String, operation: () throws -> Void) -> Never {
        do {
            try operation()
            FileHandle.standardOutput.write(Data("\(name): OK\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(name): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

if OneShotCommand.runIfRequested(arguments: CommandLine.arguments) {
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

import Foundation

public enum ClosedLidPowerManagerSelection {
    public static let usePrivilegedHelperKey = "UsePrivilegedHelper"

    public static func make(
        userDefaults: UserDefaults = .standard,
        helperStatus: PrivilegedHelperStatus = PrivilegedHelperInstaller().status
    ) -> ClosedLidPowerManaging {
        guard shouldUsePrivilegedHelper(userDefaults: userDefaults, helperStatus: helperStatus) else {
            return AdminClosedLidPowerManager()
        }

        return PrivilegedHelperClosedLidPowerManager()
    }

    public static func shouldUsePrivilegedHelper(
        userDefaults: UserDefaults = .standard,
        helperStatus: PrivilegedHelperStatus = PrivilegedHelperInstaller().status
    ) -> Bool {
        guard helperStatus == .enabled else {
            return false
        }

        guard userDefaults.object(forKey: usePrivilegedHelperKey) != nil else {
            return true
        }

        return userDefaults.bool(forKey: usePrivilegedHelperKey)
    }
}

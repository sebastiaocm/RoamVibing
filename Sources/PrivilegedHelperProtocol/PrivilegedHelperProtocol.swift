import Foundation

public enum PrivilegedHelperConstants {
    public static let appBundleIdentifier = "com.local.RoamVibing"
    public static let helperBundleIdentifier = "com.local.RoamVibing.PrivilegedHelper"
    public static let launchdLabel = "com.local.RoamVibing.PrivilegedHelper"
    public static let machServiceName = launchdLabel
    public static let launchDaemonPlistName = "\(launchdLabel).plist"
    public static let helperExecutableName = "RoamVibingPrivilegedHelper"
}

@objc(RoamVibingPrivilegedHelperProtocol)
public protocol RoamVibingPrivilegedHelperProtocol {
    func setClosedLidBypassEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
}

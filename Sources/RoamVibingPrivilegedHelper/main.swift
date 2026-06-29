import Darwin
import Foundation
import PrivilegedHelperCore
import PrivilegedHelperProtocol

do {
    let teamIdentifier = try CurrentProcessCodeSigningIdentity.teamIdentifier()
    let appCodeSigningRequirement = try CodeSigningRequirement.release(
        bundleIdentifier: PrivilegedHelperConstants.appBundleIdentifier,
        teamIdentifier: teamIdentifier
    )
    let listener = try PrivilegedHelperListener(appCodeSigningRequirement: appCodeSigningRequirement)
    listener.run()
} catch {
    let message = "RoamVibingPrivilegedHelper failed to start: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}

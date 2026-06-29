import Foundation
import PrivilegedHelperProtocol

public protocol PrivilegedHelperPowerCommanding: AnyObject {
    func setClosedLidBypassEnabled(_ enabled: Bool) throws
}

extension PrivilegedHelperPowerCommand: PrivilegedHelperPowerCommanding {}

public final class PrivilegedHelperService: NSObject, RoamVibingPrivilegedHelperProtocol {
    private let powerCommand: PrivilegedHelperPowerCommanding

    public init(powerCommand: PrivilegedHelperPowerCommanding = PrivilegedHelperPowerCommand()) {
        self.powerCommand = powerCommand
    }

    public func setClosedLidBypassEnabled(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try powerCommand.setClosedLidBypassEnabled(enabled)
            reply(true, nil)
        } catch {
            reply(false, friendlyMessage(for: error))
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

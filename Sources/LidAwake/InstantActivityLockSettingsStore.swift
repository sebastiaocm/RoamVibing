import Foundation
import LidAwakeCore

final class InstantActivityLockSettingsStore {
    private enum Key {
        static let isEnabled = "InstantActivityLock.isEnabled"
        static let idleArmingDelay = "InstantActivityLock.idleArmingDelay"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var policy: InstantActivityLockPolicy {
        get {
            let isEnabled: Bool
            if defaults.object(forKey: Key.isEnabled) == nil {
                isEnabled = true
            } else {
                isEnabled = defaults.bool(forKey: Key.isEnabled)
            }

            let storedDelay = defaults.double(forKey: Key.idleArmingDelay)
            let idleArmingDelay = storedDelay == 0
                ? InstantActivityLockPolicy.defaultIdleArmingDelay
                : storedDelay

            return InstantActivityLockPolicy(
                isEnabled: isEnabled,
                idleArmingDelay: idleArmingDelay
            )
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Key.isEnabled)
            defaults.set(newValue.idleArmingDelay, forKey: Key.idleArmingDelay)
        }
    }
}

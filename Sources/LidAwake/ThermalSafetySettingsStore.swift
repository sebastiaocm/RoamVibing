import Foundation
import LidAwakeCore

final class ThermalSafetySettingsStore {
    private enum Key {
        static let isEnabled = "ThermalSafety.isEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var policy: ThermalSafetyPolicy {
        get {
            let isEnabled: Bool
            if defaults.object(forKey: Key.isEnabled) == nil {
                isEnabled = ThermalSafetyPolicy.default.isEnabled
            } else {
                isEnabled = defaults.bool(forKey: Key.isEnabled)
            }

            return ThermalSafetyPolicy(isEnabled: isEnabled)
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Key.isEnabled)
        }
    }
}

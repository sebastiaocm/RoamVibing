import Foundation
import LidAwakeCore

final class BatterySafetySettingsStore {
    private enum Key {
        static let isEnabled = "BatterySafety.isEnabled"
        static let thresholdPercentage = "BatterySafety.thresholdPercentage"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var policy: LowBatteryPolicy {
        get {
            let isEnabled: Bool
            if defaults.object(forKey: Key.isEnabled) == nil {
                isEnabled = true
            } else {
                isEnabled = defaults.bool(forKey: Key.isEnabled)
            }

            let storedThreshold = defaults.integer(forKey: Key.thresholdPercentage)
            let threshold = storedThreshold == 0
                ? LowBatteryPolicy.defaultThresholdPercentage
                : storedThreshold

            return LowBatteryPolicy(
                isEnabled: isEnabled,
                thresholdPercentage: threshold
            )
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Key.isEnabled)
            defaults.set(newValue.thresholdPercentage, forKey: Key.thresholdPercentage)
        }
    }
}

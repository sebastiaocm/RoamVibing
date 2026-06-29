import Foundation
import LidAwakeCore

final class MuteOnLidCloseSettingsStore {
    private enum Key {
        static let isEnabled = "MuteOnLidClose.isEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var policy: MuteOnLidClosePolicy {
        get {
            let isEnabled: Bool
            if defaults.object(forKey: Key.isEnabled) == nil {
                isEnabled = MuteOnLidClosePolicy.default.isEnabled
            } else {
                isEnabled = defaults.bool(forKey: Key.isEnabled)
            }

            return MuteOnLidClosePolicy(isEnabled: isEnabled)
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Key.isEnabled)
        }
    }
}

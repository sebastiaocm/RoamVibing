import Foundation
import IOKit.ps
import LidAwakeCore

final class IOKitBatteryReader: BatteryReadingProviding {
    func currentBatteryReading() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
                let maximumCapacity = description[kIOPSMaxCapacityKey] as? Int,
                maximumCapacity > 0
            else {
                continue
            }

            let percentage = Int((Double(currentCapacity) / Double(maximumCapacity) * 100).rounded())
            let state = description[kIOPSPowerSourceStateKey] as? String
            return BatteryReading(
                percentage: percentage,
                isRunningOnBattery: state == kIOPSBatteryPowerValue
            )
        }

        return nil
    }
}

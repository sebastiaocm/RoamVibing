import Foundation
import IOKit
import LidAwakeCore

final class MacLidStateReader: LidStateProviding {
    private let clamshellStateKey = "AppleClamshellState" as CFString

    func currentLidState() -> LidState {
        let rootDomain = IORegistryEntryFromPath(
            kIOMainPortDefault,
            "IOService:/IOResources/IOPMrootDomain"
        )
        guard rootDomain != 0 else {
            return .unknown
        }
        defer { IOObjectRelease(rootDomain) }

        guard let value = IORegistryEntryCreateCFProperty(
            rootDomain,
            clamshellStateKey,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool else {
            return .unknown
        }

        return value ? .closed : .open
    }
}

import Foundation
import IOKit.pwr_mgt
import LidAwakeCore

final class IOKitAssertionManager: AssertionManaging {
    private var assertionIDs: [IOPMAssertionID] = []

    func acquire() throws {
        release()

        do {
            try createAssertion(
                type: kIOPMAssertPreventUserIdleSystemSleep,
                reason: "RoamVibing is preventing idle system sleep."
            )
            try createAssertion(
                type: kIOPMAssertPreventUserIdleDisplaySleep,
                reason: "RoamVibing is preventing idle display sleep."
            )
            try createAssertion(
                type: kIOPMAssertPreventDiskIdle,
                reason: "RoamVibing is preventing disk idle for active work."
            )
            try createAssertion(
                type: kIOPMAssertNetworkClientActive,
                reason: "RoamVibing is keeping network activity available."
            )
        } catch {
            release()
            throw error
        }
    }

    func release() {
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
        assertionIDs.removeAll()
    }

    private func createAssertion(type: String, reason: String) throws {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            throw AssertionError(type: type, result: result)
        }

        assertionIDs.append(assertionID)
    }
}

struct AssertionError: LocalizedError, Equatable {
    let type: String
    let result: IOReturn

    var errorDescription: String? {
        "Could not create \(type) power assertion. IOKit returned \(result)."
    }
}

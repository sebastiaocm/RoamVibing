import CoreAudio
import Foundation
import LidAwakeCore

final class MacAudioOutputMuter: AudioOutputMuting {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let mainElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)

    func muteActiveOutputDevices() throws {
        var firstReadError: Error?
        var firstWriteError: Error?
        var deviceIDs: [AudioObjectID] = []

        appendDevice(
            propertySelector: kAudioHardwarePropertyDefaultOutputDevice,
            to: &deviceIDs,
            firstError: &firstReadError
        )
        appendDevice(
            propertySelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            to: &deviceIDs,
            firstError: &firstReadError
        )

        for deviceID in allAudioDevices(firstError: &firstReadError) {
            if isOutputDeviceRunning(deviceID, firstError: &firstReadError) {
                deviceIDs.append(deviceID)
            }
        }

        let candidateDeviceIDs = orderedUniqueDeviceIDs(deviceIDs)
        let candidateTargetCount = candidateDeviceIDs.count
        var successfulMuteCount = 0
        for deviceID in candidateDeviceIDs {
            guard supportsMute(deviceID) else {
                continue
            }

            do {
                try setMute(true, for: deviceID)
                successfulMuteCount += 1
            } catch {
                if firstWriteError == nil {
                    firstWriteError = error
                }
            }
        }

        if let firstWriteError {
            throw firstWriteError
        }

        if successfulMuteCount == 0 {
            if let firstReadError, candidateTargetCount == 0 {
                throw firstReadError
            }
            throw MacAudioOutputMuterError.noMutableOutputDevice
        }
    }

    private func appendDevice(
        propertySelector: AudioObjectPropertySelector,
        to deviceIDs: inout [AudioObjectID],
        firstError: inout Error?
    ) {
        do {
            let deviceID = try readAudioObjectID(
                objectID: systemObjectID,
                selector: propertySelector,
                scope: kAudioObjectPropertyScopeGlobal
            )
            if deviceID != kAudioObjectUnknown {
                deviceIDs.append(deviceID)
            }
        } catch {
            if firstError == nil {
                firstError = error
            }
        }
    }

    private func allAudioDevices(firstError: inout Error?) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: mainElement
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            if firstError == nil {
                firstError = MacAudioOutputMuterError(
                    operation: "read audio device list size",
                    status: status
                )
            }
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard deviceCount > 0 else {
            return []
        }

        var devices = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: deviceCount)
        status = devices.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(kAudioHardwareUnspecifiedError)
            }

            return AudioObjectGetPropertyData(
                systemObjectID,
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }

        guard status == noErr else {
            if firstError == nil {
                firstError = MacAudioOutputMuterError(
                    operation: "read audio device list",
                    status: status
                )
            }
            return []
        }

        return devices.filter { $0 != kAudioObjectUnknown }
    }

    private func isOutputDeviceRunning(
        _ deviceID: AudioObjectID,
        firstError: inout Error?
    ) -> Bool {
        do {
            let isRunning = try readUInt32(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                scope: kAudioObjectPropertyScopeGlobal
            )
            return isRunning != 0 && hasOutputStreams(deviceID, firstError: &firstError)
        } catch MacAudioOutputMuterError.propertyUnsupported {
            return false
        } catch {
            if firstError == nil {
                firstError = error
            }
            return false
        }
    }

    private func hasOutputStreams(
        _ deviceID: AudioObjectID,
        firstError: inout Error?
    ) -> Bool {
        do {
            return try readPropertyDataSize(
                objectID: deviceID,
                selector: kAudioDevicePropertyStreams,
                scope: kAudioDevicePropertyScopeOutput
            ) > 0
        } catch MacAudioOutputMuterError.propertyUnsupported {
            return false
        } catch {
            if firstError == nil {
                firstError = error
            }
            return false
        }
    }

    private func supportsMute(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: mainElement
        )

        // Devices without a settable main output mute have no uniform system-wide CoreAudio mute.
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var isSettable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    private func setMute(_ isMuted: Bool, for deviceID: AudioObjectID) throws {
        var muteValue: UInt32 = isMuted ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: mainElement
        )
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            dataSize,
            &muteValue
        )

        guard status == noErr else {
            throw MacAudioOutputMuterError(operation: "mute audio device", status: status)
        }
    }

    private func readAudioObjectID(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> AudioObjectID {
        var value = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: mainElement
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            throw MacAudioOutputMuterError.propertyUnsupported
        }

        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )

        guard status == noErr else {
            throw MacAudioOutputMuterError(operation: "read audio property", status: status)
        }

        return value
    }

    private func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> UInt32 {
        var value: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: mainElement
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            throw MacAudioOutputMuterError.propertyUnsupported
        }

        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )

        guard status == noErr else {
            throw MacAudioOutputMuterError(operation: "read audio property", status: status)
        }

        return value
    }

    private func readPropertyDataSize(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: mainElement
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            throw MacAudioOutputMuterError.propertyUnsupported
        }

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw MacAudioOutputMuterError(operation: "read audio property data size", status: status)
        }

        return dataSize
    }

    private func orderedUniqueDeviceIDs(_ deviceIDs: [AudioObjectID]) -> [AudioObjectID] {
        var seen = Set<AudioObjectID>()
        return deviceIDs.filter { seen.insert($0).inserted }
    }
}

private enum MacAudioOutputMuterError: Error, CustomStringConvertible {
    case propertyUnsupported
    case noMutableOutputDevice
    case coreAudio(operation: String, status: OSStatus)

    init(operation: String, status: OSStatus) {
        self = .coreAudio(operation: operation, status: status)
    }

    var description: String {
        switch self {
        case .propertyUnsupported:
            return "CoreAudio property is unsupported."
        case .noMutableOutputDevice:
            return "No active output device exposes a mutable main output mute."
        case let .coreAudio(operation, status):
            return "CoreAudio failed to \(operation) with status \(status)."
        }
    }
}

extension MacAudioOutputMuterError: LocalizedError {
    var errorDescription: String? {
        description
    }
}

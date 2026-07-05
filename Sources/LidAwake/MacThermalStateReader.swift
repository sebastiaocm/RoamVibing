import Foundation
import LidAwakeCore

final class MacThermalStateReader: ThermalStateProviding {
    func currentThermalState() -> ThermalPressureState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .critical
        }
    }
}

public enum ThermalPressureState: Equatable {
    case nominal
    case fair
    case serious
    case critical

    public var shouldStopRoamVibingSession: Bool {
        switch self {
        case .nominal, .fair:
            return false
        case .serious, .critical:
            return true
        }
    }
}

public protocol ThermalStateProviding: AnyObject {
    func currentThermalState() -> ThermalPressureState
}

public struct ThermalSafetyPolicy: Equatable {
    public static let `default` = ThermalSafetyPolicy(isEnabled: true)

    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

public enum ThermalSafetyGuardResult: Equatable {
    case noAction
    case stoppedSession(state: ThermalPressureState)
}

public final class ThermalSafetyGuard {
    private let session: AwakeSession
    private let thermalStateReader: ThermalStateProviding

    public var policy: ThermalSafetyPolicy

    public init(
        session: AwakeSession,
        thermalStateReader: ThermalStateProviding,
        policy: ThermalSafetyPolicy
    ) {
        self.session = session
        self.thermalStateReader = thermalStateReader
        self.policy = policy
    }

    public func evaluate() throws -> ThermalSafetyGuardResult {
        guard policy.isEnabled, session.state != .stopped else {
            return .noAction
        }

        let state = thermalStateReader.currentThermalState()
        guard state.shouldStopRoamVibingSession else {
            return .noAction
        }

        try session.stop(intent: .safety)
        return .stoppedSession(state: state)
    }
}

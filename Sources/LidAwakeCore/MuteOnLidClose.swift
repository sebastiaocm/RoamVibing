public protocol AudioOutputMuting: AnyObject {
    func muteActiveOutputDevices() throws
}

public struct MuteOnLidClosePolicy: Equatable {
    public static let `default` = MuteOnLidClosePolicy(isEnabled: true)

    public var isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

public enum MuteOnLidCloseResult: Equatable {
    case noAction
    case muted
}

public final class MuteOnLidCloseGuard {
    private let lidStateReader: LidStateProviding
    private let audioOutputMuter: AudioOutputMuting
    private var lastLidState: LidState?
    private var hasMutedDuringCurrentClosure = false
    private var shouldBaselineOnNextEnabledEvaluation = false

    public var policy: MuteOnLidClosePolicy {
        didSet {
            if !oldValue.isEnabled, policy.isEnabled {
                shouldBaselineOnNextEnabledEvaluation = true
            }
        }
    }

    public init(
        lidStateReader: LidStateProviding,
        audioOutputMuter: AudioOutputMuting,
        policy: MuteOnLidClosePolicy
    ) {
        self.lidStateReader = lidStateReader
        self.audioOutputMuter = audioOutputMuter
        self.policy = policy
    }

    public func reset() {
        lastLidState = nil
        hasMutedDuringCurrentClosure = false
        shouldBaselineOnNextEnabledEvaluation = false
    }

    public func evaluate() throws -> MuteOnLidCloseResult {
        let lidState = lidStateReader.currentLidState()

        if policy.isEnabled, shouldBaselineOnNextEnabledEvaluation {
            lastLidState = lidState
            hasMutedDuringCurrentClosure = false
            shouldBaselineOnNextEnabledEvaluation = false
            return .noAction
        }

        guard policy.isEnabled else {
            lastLidState = lidState
            hasMutedDuringCurrentClosure = false
            return .noAction
        }

        switch lidState {
        case .open:
            lastLidState = .open
            hasMutedDuringCurrentClosure = false
            return .noAction
        case .unknown:
            return .noAction
        case .closed:
            guard lastLidState != .closed, !hasMutedDuringCurrentClosure else {
                lastLidState = .closed
                return .noAction
            }

            lastLidState = .closed
            hasMutedDuringCurrentClosure = true
            try audioOutputMuter.muteActiveOutputDevices()
            return .muted
        }
    }
}

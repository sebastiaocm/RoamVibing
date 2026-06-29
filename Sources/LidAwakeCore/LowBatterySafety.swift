public struct BatteryReading: Equatable {
    public let percentage: Int
    public let isRunningOnBattery: Bool

    public init(percentage: Int, isRunningOnBattery: Bool) {
        self.percentage = percentage
        self.isRunningOnBattery = isRunningOnBattery
    }
}

public protocol BatteryReadingProviding: AnyObject {
    func currentBatteryReading() -> BatteryReading?
}

public struct LowBatteryPolicy: Equatable {
    public static let defaultThresholdPercentage = 20

    public let isEnabled: Bool
    public let thresholdPercentage: Int

    public init(isEnabled: Bool, thresholdPercentage: Int) {
        self.isEnabled = isEnabled
        self.thresholdPercentage = min(max(thresholdPercentage, 1), 100)
    }
}

public enum LowBatteryGuardResult: Equatable {
    case noAction
    case stoppedSession(percentage: Int, threshold: Int)
}

public final class LowBatteryGuard {
    private let session: AwakeSession
    private let batteryReader: BatteryReadingProviding
    public var policy: LowBatteryPolicy

    public init(session: AwakeSession, batteryReader: BatteryReadingProviding, policy: LowBatteryPolicy) {
        self.session = session
        self.batteryReader = batteryReader
        self.policy = policy
    }

    public func evaluate() throws -> LowBatteryGuardResult {
        guard policy.isEnabled, session.state != .stopped else {
            return .noAction
        }

        guard let reading = batteryReader.currentBatteryReading(),
              reading.isRunningOnBattery,
              reading.percentage <= policy.thresholdPercentage
        else {
            return .noAction
        }

        try session.stop(intent: .safety)
        return .stoppedSession(
            percentage: reading.percentage,
            threshold: policy.thresholdPercentage
        )
    }
}

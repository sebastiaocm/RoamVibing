import Darwin
import Dispatch
import Foundation

public protocol PrivilegedHelperProcessRunning: AnyObject {
    func run(executablePath: String, arguments: [String], timeout: TimeInterval) throws -> String
}

public final class PrivilegedHelperPowerCommand {
    private let processRunner: PrivilegedHelperProcessRunning
    private let commandTimeout: TimeInterval

    public init(
        processRunner: PrivilegedHelperProcessRunning = FoundationPrivilegedHelperProcessRunner(),
        commandTimeout: TimeInterval = 5
    ) {
        self.processRunner = processRunner
        self.commandTimeout = commandTimeout
    }

    public func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        let expectedValue = enabled ? "1" : "0"
        _ = try processRunner.run(
            executablePath: "/usr/bin/pmset",
            arguments: ["-a", "disablesleep", expectedValue],
            timeout: commandTimeout
        )

        let status = try processRunner.run(
            executablePath: "/usr/bin/pmset",
            arguments: ["-g"],
            timeout: commandTimeout
        )

        guard status.split(separator: "\n").contains(where: { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" }) == ["SleepDisabled", Substring(expectedValue)]
        }) else {
            throw PrivilegedHelperPowerCommandError.verificationFailed(expectedValue: expectedValue)
        }
    }
}

public final class FoundationPrivilegedHelperProcessRunner: PrivilegedHelperProcessRunning {
    private let processDidLaunch: ((Process) -> Void)?

    public init(processDidLaunch: ((Process) -> Void)? = nil) {
        self.processDidLaunch = processDidLaunch
    }

    public func run(executablePath: String, arguments: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw PrivilegedHelperPowerCommandError.processFailed(
                executablePath: executablePath,
                status: -1,
                output: error.localizedDescription
            )
        }
        processDidLaunch?(process)

        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            waitGroup.leave()
        }

        if waitGroup.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if waitGroup.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                waitGroup.wait()
            }

            throw PrivilegedHelperPowerCommandError.timedOut(
                executablePath: executablePath,
                timeout: timeout
            )
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PrivilegedHelperPowerCommandError.processFailed(
                executablePath: executablePath,
                status: process.terminationStatus,
                output: message
            )
        }

        return message
    }
}

public enum PrivilegedHelperPowerCommandError: LocalizedError, Equatable {
    case processFailed(executablePath: String, status: Int32, output: String)
    case timedOut(executablePath: String, timeout: TimeInterval)
    case verificationFailed(expectedValue: String)

    public var errorDescription: String? {
        switch self {
        case let .processFailed(executablePath, status, output):
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOutput.isEmpty {
                return "\(executablePath) exited with status \(status)."
            }
            return "\(executablePath) exited with status \(status). \(trimmedOutput)"
        case let .timedOut(executablePath, timeout):
            return "\(executablePath) timed out after \(timeout) seconds."
        case let .verificationFailed(expectedValue):
            return "macOS did not report SleepDisabled \(expectedValue). Closed-Lid Mode was not changed."
        }
    }
}

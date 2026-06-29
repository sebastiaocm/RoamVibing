import Foundation

public protocol CommandRunning: AnyObject {
    func run(executablePath: String, arguments: [String]) throws
}

public final class AdminClosedLidPowerManager: ClosedLidPowerManaging {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func setClosedLidBypassEnabled(_ enabled: Bool) throws {
        try commandRunner.run(
            executablePath: "/usr/bin/osascript",
            arguments: ClosedLidBypassCommand.osascriptArguments(enabled: enabled)
        )
    }
}

public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw CommandRunError(
                executablePath: executablePath,
                status: process.terminationStatus,
                output: message
            )
        }
    }
}

public struct CommandRunError: LocalizedError, Equatable {
    public let executablePath: String
    public let status: Int32
    public let output: String?

    public var errorDescription: String? {
        if isAdministratorAuthenticationFailure {
            return """
            Administrator authentication failed or was canceled. Closed-Lid Mode was not changed.

            Try again. Use Touch ID if macOS offers it, or enter your Mac administrator password. You can use Normal Awake without administrator access.
            """
        }

        var description = "\(executablePath) exited with status \(status)."
        if let output, !output.isEmpty {
            description += " \(output)"
        }
        return description
    }

    private var isAdministratorAuthenticationFailure: Bool {
        guard executablePath == "/usr/bin/osascript",
              let output
        else {
            return false
        }

        return output.contains("-60005")
            || output.localizedCaseInsensitiveContains("administrator user name or password was incorrect")
            || output.contains("-128")
            || output.localizedCaseInsensitiveContains("user canceled")
    }
}

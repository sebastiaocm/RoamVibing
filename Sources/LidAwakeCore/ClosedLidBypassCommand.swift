public enum ClosedLidBypassCommand {
    public static func osascriptArguments(enabled: Bool) -> [String] {
        [
            "-e",
            appleScript(enabled: enabled)
        ]
    }

    public static func appleScript(enabled: Bool) -> String {
        let value = enabled ? "1" : "0"
        let action = enabled ? "enable" : "disable"
        let prompt = "RoamVibing needs macOS administrator approval to \(action) Closed-Lid Mode. Use Touch ID if macOS offers it, or enter your Mac administrator password."
        let command = """
        /usr/bin/pmset -a disablesleep \(value) && /usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ { if ($2 != \(value)) exit 42; found=1 } END { if (!found) exit 43 }'
        """
        return "do shell script \"\(command)\" with administrator privileges with prompt \"\(prompt)\""
    }
}

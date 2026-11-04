import Foundation

enum ShellError: Error, LocalizedError {
    case nonZeroExit(code: Int, stderr: String)
    case cancelled
    case executableNotFound(String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let stderr):
            return "Command failed with code \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .cancelled:
            return "Cancelled by user."
        case .executableNotFound(let name):
            return "Executable not found: \(name). Make sure wireguard-tools is installed (`brew install wireguard-tools`)."
        }
    }
}

struct ShellRunner {
    /// Run a shell command as administrator via `osascript`.
    /// Presents a native macOS privilege prompt.
    static func runAsAdmin(command: String, arguments: [String] = [], logURL: URL? = nil) async throws -> String {
        try await runAsAdmin(script: shellCommand(command, arguments: arguments, logURL: logURL))
    }

    /// Run a composed shell script as administrator: one privilege prompt however many commands
    /// it contains. `prompt` replaces the generic "osascript wants to make changes" text.
    static func runAsAdmin(script: String, prompt: String? = nil) async throws -> String {
        var appleScript = "do shell script \"\(escapeForAppleScript(script))\""
        if let prompt { appleScript += " with prompt \"\(escapeForAppleScript(prompt))\"" }
        appleScript += " with administrator privileges"
        return try await run("/usr/bin/osascript", arguments: ["-e", appleScript])
    }

    /// A quoted shell command line. With `logURL`, all output (including that of daemons the
    /// command leaves running, such as wireguard-go with `LOG_LEVEL` set) is appended to that file.
    static func shellCommand(_ command: String, arguments: [String], logURL: URL? = nil) -> String {
        let commandLine = command + " " + arguments.map(escapeForShell).joined(separator: " ")
        guard let logURL else { return commandLine }
        // A daemon that inherits our pipe would make `do shell script` wait for it to exit, so
        // everything goes to the file. On failure, replay the tail so callers still get the error.
        let log = escapeForShell(logURL.path)
        return "echo \"== $(date '+%F %T')\" \(escapeForShell(arguments.joined(separator: " "))) >>\(log); "
            + "LOG_LEVEL=error \(commandLine) >>\(log) 2>&1 || { rc=$?; tail -n 3 \(log) >&2; exit $rc; }"
    }

    /// Run a shell command as the current user.
    static func run(_ command: String, arguments: [String] = []) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else if process.terminationStatus == 1 && err.localizedCaseInsensitiveContains("user canceled") {
                    continuation.resume(throwing: ShellError.cancelled)
                } else {
                    continuation.resume(throwing: ShellError.nonZeroExit(code: Int(process.terminationStatus), stderr: err))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func escapeForShell(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

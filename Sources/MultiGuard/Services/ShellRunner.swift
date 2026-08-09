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
    static func runAsAdmin(command: String, arguments: [String] = []) async throws -> String {
        let shellCommand = command + " " + arguments.map(escapeForShell).joined(separator: " ")
        let script = "do shell script \"\(escapeForAppleScript(shellCommand))\" with administrator privileges"
        return try await run("/usr/bin/osascript", arguments: ["-e", script])
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

    private static func escapeForShell(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

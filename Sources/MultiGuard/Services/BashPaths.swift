import Foundation

enum BashError: Error, LocalizedError {
    case versionTooLow(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .versionTooLow(let path):
            return "Bash at \(path) is too old. Install Bash 4+ with: brew install bash"
        case .notFound:
            return "Bash 4+ not found. Install it with: brew install bash"
        }
    }
}

struct BashPaths {
    static func findBash4() async throws -> String {
        let candidates = [
            "/opt/homebrew/bin/bash",  // Apple Silicon Homebrew
            "/usr/local/bin/bash"      // Intel Homebrew
        ]

        for path in candidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            if try await isBash4OrLater(path) {
                return path
            }
        }

        // Final fallback: whatever `which bash` resolves to
        if let path = try? await ShellRunner.run("/usr/bin/which", arguments: ["bash"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            if try await isBash4OrLater(path) {
                return path
            }
            throw BashError.versionTooLow(path)
        }

        throw BashError.notFound
    }

    private static func isBash4OrLater(_ path: String) async throws -> Bool {
        let output = try await ShellRunner.run(path, arguments: ["--version"])
        guard let major = parseMajorVersion(output), major >= 4 else { return false }
        return true
    }

    private static func parseMajorVersion(_ output: String) -> Int? {
        // Typical output: "GNU bash, version 5.2.15(1)-release ..."
        let prefix = "GNU bash, version "
        guard let range = output.range(of: prefix) else { return nil }
        let remainder = output[range.upperBound...]
        guard let dotIndex = remainder.firstIndex(of: ".") else { return nil }
        return Int(remainder[..<dotIndex])
    }
}

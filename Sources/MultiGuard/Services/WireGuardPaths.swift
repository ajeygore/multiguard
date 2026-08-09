import Foundation

struct WireGuardPaths {
    static func findExecutable(_ name: String) async throws -> String {
        let candidates = [
            "/opt/homebrew/bin/\(name)", // Apple Silicon Homebrew
            "/usr/local/bin/\(name)",    // Intel Homebrew
            "/usr/bin/\(name)"           // System
        ]

        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: PATH lookup
        if let path = try? await ShellRunner.run("/usr/bin/which", arguments: [name])
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        throw ShellError.executableNotFound(name)
    }
}

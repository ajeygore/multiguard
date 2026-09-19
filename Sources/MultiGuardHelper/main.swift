import Foundation

class MultiGuardHelper: NSObject, MultiGuardHelperProtocol, NSXPCListenerDelegate {
    private let listener: NSXPCListener

    override init() {
        self.listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
        super.init()
        self.listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.current.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Only accept connections from the signed MultiGuard app.
        guard let code = SecCodeCreateWithPID(newConnection.processIdentifier),
              let requirement = SecRequirementCreate(string: HelperConstants.authorizedClientRequirement),
              SecCodeCheckValidity(code, [], requirement) else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: MultiGuardHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func ping(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func connect(withConfigPath configPath: String, reply: @escaping (String?, Error?) -> Void) {
        do {
            let interface = try runWGQuick(action: "up", configPath: configPath)
            reply(interface, nil)
        } catch {
            reply(nil, error)
        }
    }

    func disconnect(withConfigPath configPath: String, reply: @escaping (Error?) -> Void) {
        do {
            _ = try runWGQuick(action: "down", configPath: configPath)
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func stats(forInterface interface: String, reply: @escaping (String?, Error?) -> Void) {
        // Only accept plausible interface names so this can't be used to pass arbitrary arguments to wg.
        guard interface.range(of: "^[A-Za-z0-9_.-]{1,32}$", options: .regularExpression) != nil else {
            reply(nil, HelperError.commandFailed(1, "Invalid interface name"))
            return
        }
        do {
            let wg = try findExecutable("wg")
            let dump = try runProcess(executable: wg, arguments: ["show", interface, "dump"])
            reply(stripPrivateKey(fromDump: dump), nil)
        } catch {
            reply(nil, error)
        }
    }

    /// The first line of `wg show <iface> dump` is `<private-key>\t<public-key>\t<port>\t<fwmark>`.
    /// Replace the private key with "(none)" so it never leaves the helper.
    private func stripPrivateKey(fromDump dump: String) -> String {
        var lines = dump.components(separatedBy: "\n")
        guard let first = lines.first, !first.isEmpty else { return dump }
        var fields = first.components(separatedBy: "\t")
        if !fields.isEmpty {
            fields[0] = "(none)"
            lines[0] = fields.joined(separator: "\t")
        }
        return lines.joined(separator: "\n")
    }

    private func runWGQuick(action: String, configPath: String) throws -> String {
        let wgQuick = try findExecutable("wg-quick")
        let bash = try findExecutable("bash")

        // Verify bash is 4+.
        let versionOutput = try runProcess(executable: bash, arguments: ["--version"])
        guard let major = parseBashMajorVersion(versionOutput), major >= 4 else {
            throw HelperError.bashTooOld
        }

        try runProcess(executable: bash, arguments: [wgQuick, action, configPath], captureOutput: false)

        // Discover the assigned utun interface.
        let wg = try findExecutable("wg")
        let interfacesOutput = try runProcess(executable: wg, arguments: ["show", "interfaces"])
        let interfaces = interfacesOutput.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // For disconnect, we don't need to discover the interface.
        if action == "down" { return "" }

        // For a fresh connect, the interface we just created is likely the last one listed.
        return interfaces.last ?? "unknown"
    }

    private func findExecutable(_ name: String) throws -> String {
        let candidates: [String]
        switch name {
        case "wg-quick", "wg":
            candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        case "bash":
            candidates = ["/opt/homebrew/bin/bash", "/usr/local/bin/bash", "/bin/bash"]
        default:
            candidates = []
        }

        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) { return path }
        }
        throw HelperError.executableNotFound(name)
    }

    @discardableResult
    private func runProcess(executable: String, arguments: [String], captureOutput: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        if captureOutput {
            process.standardOutput = stdout
            process.standardError = stderr
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw HelperError.commandFailed(Int(process.terminationStatus), err)
        }

        return captureOutput
            ? String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            : ""
    }

    private func parseBashMajorVersion(_ output: String) -> Int? {
        let prefix = "GNU bash, version "
        guard let range = output.range(of: prefix) else { return nil }
        let remainder = output[range.upperBound...]
        guard let dotIndex = remainder.firstIndex(of: ".") else { return nil }
        return Int(remainder[..<dotIndex])
    }
}

enum HelperError: Error, LocalizedError {
    case bashTooOld
    case executableNotFound(String)
    case commandFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .bashTooOld:
            return "Bash 4+ is required. Install with: brew install bash"
        case .executableNotFound(let name):
            return "Executable not found: \(name)"
        case .commandFailed(let code, let stderr):
            return "Command failed with code \(code): \(stderr)"
        }
    }
}

struct HelperConstants {
    static let machServiceName = "com.multiguard.helper"

    // This requirement must match the main app's signing identifier.
    // Replace 'TEAM_ID' with your actual Apple Developer Team ID.
    static let authorizedClientRequirement = "identifier \"com.multiguard.app\" and anchor apple generic and certificate leaf[subject.OU] = \"TEAM_ID\""
}

// MARK: - SecCode helpers

func SecCodeCreateWithPID(_ pid: pid_t) -> SecCode? {
    var code: SecCode?
    let status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code)
    guard status == errSecSuccess else { return nil }
    return code
}

func SecRequirementCreate(string: String) -> SecRequirement? {
    var requirement: SecRequirement?
    let status = SecRequirementCreateWithString(string as CFString, [], &requirement)
    guard status == errSecSuccess else { return nil }
    return requirement
}

func SecCodeCheckValidity(_ code: SecCode, _ flags: SecCSFlags, _ requirement: SecRequirement?) -> Bool {
    let status = SecCodeCheckValidityWithErrors(code, flags, requirement, nil)
    return status == errSecSuccess
}

let helper = MultiGuardHelper()
helper.run()

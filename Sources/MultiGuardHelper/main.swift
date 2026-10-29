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
        guard let clientRequirement = HelperConstants.authorizedClientRequirement,
              let code = SecCodeCreateWithPID(newConnection.processIdentifier),
              let requirement = SecRequirementCreate(string: clientRequirement),
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

    // NSXPCConnection delivers messages one at a time per connection. Each request therefore runs on
    // a global queue, so a `wg show` stuck on a hung wireguard-go socket can't hold up a disconnect.
    // Errors go out as plain NSErrors with an explicit description: a Swift LocalizedError loses its
    // message when it crosses the XPC boundary.

    func connect(withConfigPath configPath: String, reply: @escaping (String?, Error?) -> Void) {
        DispatchQueue.global().async {
            do {
                let interface = try self.runWGQuick(action: "up", configPath: configPath)
                reply(interface, nil)
            } catch {
                reply(nil, xpcError(error))
            }
        }
    }

    func disconnect(withConfigPath configPath: String, reply: @escaping (Error?) -> Void) {
        DispatchQueue.global().async {
            do {
                _ = try self.runWGQuick(action: "down", configPath: configPath)
                reply(nil)
            } catch {
                reply(xpcError(error))
            }
        }
    }

    func stats(forInterface interface: String, reply: @escaping (String?, Error?) -> Void) {
        // Only accept plausible interface names so this can't be used to pass arbitrary arguments to wg.
        guard interface.range(of: "^[A-Za-z0-9_.-]{1,32}$", options: .regularExpression) != nil else {
            reply(nil, xpcError(HelperError.commandFailed(1, "Invalid interface name")))
            return
        }
        DispatchQueue.global().async {
            do {
                let wg = try self.findExecutable("wg")
                let dump = try self.runProcess(executable: wg, arguments: ["show", interface, "dump"], timeout: 5)
                reply(self.stripPrivateKey(fromDump: dump), nil)
            } catch {
                reply(nil, xpcError(error))
            }
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

        // wg-quick talks to wireguard-go through `wg`; if that daemon hangs, so does wg-quick.
        try runProcess(executable: bash, arguments: [wgQuick, action, configPath], timeout: 30)

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

    /// Run a process and return its stdout. It is killed after `timeout` seconds, so a hung child
    /// (e.g. `wg` blocked on an unresponsive wireguard-go socket) can't block the helper forever.
    @discardableResult
    private func runProcess(executable: String, arguments: [String], timeout: TimeInterval = 10) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        // launchd starts the helper with PATH=/usr/bin:/bin:/usr/sbin:/sbin; wg-quick looks up `wg`
        // and Homebrew's bash through PATH, so put the Homebrew prefixes first.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        // Collect output as it arrives instead of reading to EOF: `wg-quick up` leaves wireguard-go
        // and its route monitor running in the background with these pipes inherited, so EOF never
        // comes. Reading concurrently also keeps a full pipe buffer from stalling the child.
        let outBuffer = OutputBuffer()
        let errBuffer = OutputBuffer()
        // At EOF the handler fires again and again with empty data until it is removed — a busy
        // loop that burned two cores while the 2 s stats poll was running. Remove it on EOF.
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { outBuffer.append(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { errBuffer.append(chunk) }
        }
        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                finished.wait()
            }
            throw HelperError.timedOut(([executable] + arguments).joined(separator: " "), timeout)
        }
        // Let the readability handlers pick up whatever the process wrote just before exiting.
        Thread.sleep(forTimeInterval: 0.1)

        if process.terminationStatus != 0 {
            throw HelperError.commandFailed(Int(process.terminationStatus), errBuffer.string)
        }
        return outBuffer.string
    }

    private func parseBashMajorVersion(_ output: String) -> Int? {
        // Localized: German prints "GNU bash, Version 5.3.20(1)-release".
        let prefix = "GNU bash, version "
        guard let range = output.range(of: prefix, options: .caseInsensitive) else { return nil }
        let remainder = output[range.upperBound...]
        guard let dotIndex = remainder.firstIndex(of: ".") else { return nil }
        return Int(remainder[..<dotIndex])
    }
}

enum HelperError: Error, LocalizedError {
    case bashTooOld
    case executableNotFound(String)
    case commandFailed(Int, String)
    case timedOut(String, TimeInterval)

    var errorDescription: String? {
        switch self {
        case .bashTooOld:
            return "Bash 4+ is required. Install with: brew install bash"
        case .executableNotFound(let name):
            return "Executable not found: \(name)"
        case .commandFailed(let code, let stderr):
            return "Command failed with code \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .timedOut(let command, let seconds):
            return "Timed out after \(Int(seconds)) s: \(command)"
        }
    }
}

struct HelperConstants {
    static let machServiceName = "com.multiguard.helper"

    /// Only the MultiGuard app signed by the same team as this helper may connect. The team is read
    /// from the helper's own signature, so no team ID has to be compiled in. Nil (reject everyone)
    /// when the helper itself carries no team, e.g. an ad-hoc build.
    static let authorizedClientRequirement: String? = {
        guard let team = ownTeamIdentifier() else { return nil }
        return "identifier \"com.multiguard.app\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }()

    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// Thread-safe accumulator for process output delivered by `readabilityHandler`.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// An NSError that keeps its message across XPC (see the note above `connect`).
func xpcError(_ error: Error) -> NSError {
    NSError(domain: HelperConstants.machServiceName, code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
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

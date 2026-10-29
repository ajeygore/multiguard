import Foundation
import Security
import ServiceManagement

enum HelperManagerError: Error, LocalizedError {
    case installationFailed(String)
    case connectionFailed
    case helperNotFound
    case notSigned
    case timedOut(Int)
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .installationFailed(let msg):
            return "Failed to install privileged helper: \(msg)"
        case .connectionFailed:
            return "Failed to connect to privileged helper."
        case .helperNotFound:
            return "Privileged helper not installed."
        case .notSigned:
            return "The app must be code-signed with an Apple Developer ID to install a privileged helper."
        case .timedOut(let seconds):
            return "The privileged helper did not answer within \(seconds) s."
        case .unreachable(let msg):
            return "Lost connection to privileged helper: \(msg)"
        }
    }
}

@MainActor
final class HelperManager: ObservableObject {
    static let shared = HelperManager()

    @Published var isInstalled = false

    private var connection: NSXPCConnection?
    private let helperBundleName = "com.multiguard.helper"
    private let helperMachServiceName = "com.multiguard.helper"
    private let launchdPlistName = "com.multiguard.helper.plist"

    /// How long to wait for the helper to answer a ping before giving up on it.
    private let pingTimeout: TimeInterval = 3

    private init() {}

    /// The helper only accepts clients signed with a Developer ID team, so for ad-hoc
    /// (development) builds it can never work and must not be registered at all.
    static let isDeveloperSigned: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return dict[kSecCodeInfoTeamIdentifier as String] is String
    }()

    func install() async throws {
        let service = SMAppService.daemon(plistName: launchdPlistName)
        guard Self.isDeveloperSigned else {
            // Remove a registration left behind by an earlier build: launchd would keep it in
            // "spawn scheduled" forever and every XPC call to it would go unanswered.
            if service.status != .notRegistered {
                try? await service.unregister()
            }
            throw HelperManagerError.notSigned
        }
        if service.status == .enabled {
            isInstalled = true
            return
        }
        do {
            try service.register()
            isInstalled = true
        } catch {
            // The first registration needs the user to allow the background item in
            // System Settings → General → Login Items; take them there.
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            throw HelperManagerError.installationFailed(error.localizedDescription)
        }
    }

    func connect() async throws -> NSXPCConnection {
        if let connection = connection {
            return connection
        }

        let newConnection = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: MultiGuardHelperProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        newConnection.resume()

        // Without an error handler and a timeout a helper that never starts (missing binary,
        // rejected client) leaves the ping reply pending forever, and the caller never reaches
        // the osascript fallback.
        let once = ResumeOnce()
        let pingResult = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let proxy = newConnection.remoteObjectProxyWithErrorHandler { _ in
                if once.claim() { continuation.resume(returning: false) }
            } as? MultiGuardHelperProtocol
            guard let proxy else {
                if once.claim() { continuation.resume(returning: false) }
                return
            }
            proxy.ping { result in
                if once.claim() { continuation.resume(returning: result) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + pingTimeout) {
                if once.claim() { continuation.resume(returning: false) }
            }
        }

        guard pingResult else {
            newConnection.invalidate()
            throw HelperManagerError.connectionFailed
        }

        connection = newConnection
        return newConnection
    }

    func connectTunnel(configPath: String) async throws -> String {
        try await ensureHelper()
        // wg-quick itself is limited to 30 s inside the helper; leave room for the checks around it.
        return try await call(timeout: 50) { proxy, finish in
            proxy.connect(withConfigPath: configPath) { interface, error in
                if let error = error {
                    finish(.failure(error))
                } else if let interface = interface {
                    finish(.success(interface))
                } else {
                    finish(.failure(HelperManagerError.connectionFailed))
                }
            }
        }
    }

    func disconnectTunnel(configPath: String) async throws {
        try await ensureHelper()
        try await call(timeout: 50) { proxy, finish in
            proxy.disconnect(withConfigPath: configPath) { error in
                finish(error.map { .failure($0) } ?? .success(()))
            }
        }
    }

    /// Fetch `wg show <interface> dump` through the helper. Unlike connect/disconnect this never
    /// tries to install the helper: it is polled every few seconds, so it must be cheap when the
    /// helper is unavailable (unsigned development builds).
    func tunnelStats(interface: String) async throws -> String {
        guard Self.isDeveloperSigned, isInstalled else { throw HelperManagerError.helperNotFound }
        return try await call(timeout: 8) { proxy, finish in
            proxy.stats(forInterface: interface) { dump, error in
                if let error = error {
                    finish(.failure(error))
                } else if let dump = dump {
                    finish(.success(dump))
                } else {
                    finish(.failure(HelperManagerError.connectionFailed))
                }
            }
        }
    }

    /// Send one request to the helper. The reply, a connection error and the timeout race and the
    /// first one wins: a reply that never arrives used to leave a tunnel in "Disconnecting…" forever.
    private func call<T>(
        timeout: TimeInterval,
        _ send: @escaping (MultiGuardHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let connection = try await connect()
        let once = ResumeOnce()
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let finish: (Result<T, Error>) -> Void = { result in
                    if once.claim() { continuation.resume(with: result) }
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    finish(.failure(HelperManagerError.unreachable(error.localizedDescription)))
                } as? MultiGuardHelperProtocol
                guard let proxy else {
                    finish(.failure(HelperManagerError.connectionFailed))
                    return
                }
                send(proxy, finish)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    finish(.failure(HelperManagerError.timedOut(Int(timeout))))
                }
            }
        } catch let error as HelperManagerError {
            // Start from a fresh connection next time instead of reusing one that stopped answering.
            if self.connection === connection {
                connection.invalidate()
                self.connection = nil
            }
            throw error
        }
    }

    private func ensureHelper() async throws {
        if !isInstalled {
            try await install()
        }
    }
}

/// Guards a continuation that several callbacks (reply, error handler, timeout) race to resume.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

import Foundation
import ServiceManagement

enum HelperManagerError: Error, LocalizedError {
    case installationFailed(String)
    case connectionFailed
    case helperNotFound
    case notSigned

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

    private init() {}

    func install() async throws {
        let service = SMAppService.daemon(plistName: launchdPlistName)
        do {
            try service.register()
            isInstalled = true
        } catch {
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
        connection = newConnection

        guard let proxy = newConnection.remoteObjectProxy as? MultiGuardHelperProtocol else {
            throw HelperManagerError.connectionFailed
        }

        let pingResult = await withCheckedContinuation { continuation in
            proxy.ping { result in
                continuation.resume(returning: result)
            }
        }

        guard pingResult else {
            throw HelperManagerError.connectionFailed
        }

        return newConnection
    }

    func connectTunnel(configPath: String) async throws -> String {
        try await ensureHelper()
        let connection = try await connect()
        guard let proxy = connection.remoteObjectProxy as? MultiGuardHelperProtocol else {
            throw HelperManagerError.connectionFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            proxy.connect(withConfigPath: configPath) { interface, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let interface = interface {
                    continuation.resume(returning: interface)
                } else {
                    continuation.resume(throwing: HelperManagerError.connectionFailed)
                }
            }
        }
    }

    func disconnectTunnel(configPath: String) async throws {
        try await ensureHelper()
        let connection = try await connect()
        guard let proxy = connection.remoteObjectProxy as? MultiGuardHelperProtocol else {
            throw HelperManagerError.connectionFailed
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.disconnect(withConfigPath: configPath) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func ensureHelper() async throws {
        if !isInstalled {
            try await install()
        }
    }
}

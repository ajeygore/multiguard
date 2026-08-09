import Foundation

actor TunnelManager {
    private var activeInterfaces: [UUID: String] = [:]

    func connect(_ tunnel: Tunnel) async throws -> String {
        do {
            let interface = try await HelperManager.shared.connectTunnel(configPath: tunnel.fileURL.path)
            activeInterfaces[tunnel.id] = interface
            return interface
        } catch {
            return try await fallbackConnect(tunnel)
        }
    }

    func disconnect(_ tunnel: Tunnel) async throws {
        do {
            try await HelperManager.shared.disconnectTunnel(configPath: tunnel.fileURL.path)
        } catch {
            try await fallbackDisconnect(tunnel)
        }
        activeInterfaces.removeValue(forKey: tunnel.id)
    }

    func connectTunnels(_ tunnels: [Tunnel]) async throws -> [UUID: String] {
        var interfaces: [UUID: String] = [:]
        for tunnel in tunnels {
            do {
                let interface = try await HelperManager.shared.connectTunnel(configPath: tunnel.fileURL.path)
                interfaces[tunnel.id] = interface
                activeInterfaces[tunnel.id] = interface
            } catch {
                do {
                    let interface = try await fallbackConnect(tunnel)
                    interfaces[tunnel.id] = interface
                    activeInterfaces[tunnel.id] = interface
                } catch {
                    interfaces[tunnel.id] = "unknown"
                }
            }
        }
        return interfaces
    }

    func disconnectTunnels(_ tunnels: [Tunnel]) async throws {
        for tunnel in tunnels {
            do {
                try await HelperManager.shared.disconnectTunnel(configPath: tunnel.fileURL.path)
            } catch {
                try? await fallbackDisconnect(tunnel)
            }
            activeInterfaces.removeValue(forKey: tunnel.id)
        }
    }

    // MARK: - Fallback for unsigned / development builds

    private func fallbackConnect(_ tunnel: Tunnel) async throws -> String {
        let wgQuick = try await WireGuardPaths.findExecutable("wg-quick")
        let wg = try await WireGuardPaths.findExecutable("wg")
        let bash = try await BashPaths.findBash4()

        _ = try await ShellRunner.runAsAdmin(command: bash, arguments: [wgQuick, "up", tunnel.fileURL.path])

        let interface = try await discoverInterface(for: tunnel.config, wgPath: wg)
        return interface
    }

    private func fallbackDisconnect(_ tunnel: Tunnel) async throws {
        let wgQuick = try await WireGuardPaths.findExecutable("wg-quick")
        let bash = try await BashPaths.findBash4()
        _ = try await ShellRunner.runAsAdmin(command: bash, arguments: [wgQuick, "down", tunnel.fileURL.path])
    }

    private func discoverInterface(for config: WireGuardConfig, wgPath: String) async throws -> String {
        let output = try await ShellRunner.run(wgPath, arguments: ["show", "interfaces"])
        let interfaces = output
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        for interface in interfaces {
            let dump = try? await ShellRunner.run(wgPath, arguments: ["show", interface])
            guard let dump = dump else { continue }

            for peer in config.peers {
                if dump.contains(peer.publicKey) {
                    return interface
                }
            }
        }

        return interfaces.last ?? "unknown"
    }
}

import Foundation

actor TunnelManager {
    private var activeInterfaces: [UUID: String] = [:]

    func connect(_ tunnel: Tunnel) async throws -> String {
        let interface = try await bringUp(tunnel)
        activeInterfaces[tunnel.id] = interface
        return interface
    }

    /// Helper first, osascript prompt only when the helper is unavailable.
    private func bringUp(_ tunnel: Tunnel) async throws -> String {
        do {
            return try await HelperManager.shared.connectTunnel(configPath: tunnel.fileURL.path)
        } catch where Self.shouldFallBack(error) {
            do {
                return try await fallbackConnect(tunnel)
            } catch {
                // The tunnel is already up (e.g. from a previous app session): adopt it instead of failing.
                if let interface = Self.existingInterface(from: error) { return interface }
                throw error
            }
        } catch {
            if let interface = Self.existingInterface(from: error) { return interface }
            throw error
        }
    }

    private func tearDown(_ tunnel: Tunnel) async throws {
        do {
            do {
                try await HelperManager.shared.disconnectTunnel(configPath: tunnel.fileURL.path)
            } catch where Self.shouldFallBack(error) {
                try await fallbackDisconnect(tunnel)
            }
        } catch where Self.isAlreadyDown(error) {
            // wireguard-go is gone already; nothing left to tear down.
        }
    }

    /// Fall back to the osascript prompt only when the helper is unavailable. If the helper ran
    /// wg-quick and it failed or hung, running it again as root via osascript ends the same way.
    private static func shouldFallBack(_ error: Error) -> Bool {
        guard let error = error as? HelperManagerError else { return false }
        if case .timedOut = error { return false }
        return true
    }

    /// `wg-quick down` on a tunnel whose wireguard-go has died reports "`mg_…' is not a WireGuard interface".
    private static func isAlreadyDown(_ error: Error) -> Bool {
        error.localizedDescription.contains("is not a WireGuard interface")
    }

    /// Tunnels that are already up on the system, keyed by tunnel id, discovered by matching each
    /// `utun` interface's address against the configs. Works without privileges (`wg show interfaces`
    /// and `ifconfig` are world-readable) so the app can recover state after a restart.
    func runningInterfaces(for tunnels: [Tunnel]) async -> [UUID: String] {
        guard let wg = try? await WireGuardPaths.findExecutable("wg"),
              let output = try? await ShellRunner.run(wg, arguments: ["show", "interfaces"]) else { return [:] }
        let interfaces = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var result: [UUID: String] = [:]
        for interface in interfaces {
            guard let ifconfig = try? await ShellRunner.run("/sbin/ifconfig", arguments: [interface]) else { continue }
            let addresses = Set(Self.parseAddresses(fromIfconfig: ifconfig))
            guard !addresses.isEmpty else { continue }
            for tunnel in tunnels where result[tunnel.id] == nil {
                let configured = tunnel.config.interface.addresses.map { $0.split(separator: "/").first.map(String.init) ?? $0 }
                if configured.contains(where: addresses.contains) {
                    result[tunnel.id] = interface
                    activeInterfaces[tunnel.id] = interface
                    break
                }
            }
        }
        return result
    }

    /// Interfaces with a live wireguard-go control socket, or nil if `wg` is unavailable.
    /// `wg show interfaces` only checks that each socket accepts a connection and sends no request,
    /// so unlike `wg show <iface>` it doesn't block on a hung wireguard-go.
    func liveInterfaces() async -> Set<String>? {
        guard let wg = try? await WireGuardPaths.findExecutable("wg"),
              let output = try? await ShellRunner.run(wg, arguments: ["show", "interfaces"]) else { return nil }
        return Set(output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
    }

    /// wg-quick reports "`name' already exists as `utunN'" when the interface is still up.
    private static func existingInterface(from error: Error) -> String? {
        let message = error.localizedDescription
        guard let range = message.range(of: "already exists as `") else { return nil }
        let rest = message[range.upperBound...]
        guard let end = rest.firstIndex(of: "'") else { return nil }
        let name = String(rest[..<end])
        return name.isEmpty ? nil : name
    }

    /// `inet 10.0.0.2 --> 10.0.0.2 netmask …` / `inet6 fd00::2 prefixlen 64` lines from `ifconfig`.
    private static func parseAddresses(fromIfconfig output: String) -> [String] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard parts.count >= 2, parts[0] == "inet" || parts[0] == "inet6" else { return nil }
            // Strip an IPv6 zone suffix such as fe80::1%utun6.
            return parts[1].split(separator: "%").first.map(String.init)
        }
    }

    func disconnect(_ tunnel: Tunnel) async throws {
        try await tearDown(tunnel)
        activeInterfaces.removeValue(forKey: tunnel.id)
    }

    func connectTunnels(_ tunnels: [Tunnel]) async throws -> [UUID: String] {
        var interfaces: [UUID: String] = [:]
        for tunnel in tunnels {
            let interface = (try? await bringUp(tunnel)) ?? "unknown"
            interfaces[tunnel.id] = interface
            if interface != "unknown" { activeInterfaces[tunnel.id] = interface }
        }
        return interfaces
    }

    func disconnectTunnels(_ tunnels: [Tunnel]) async throws {
        for tunnel in tunnels {
            try? await tearDown(tunnel)
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

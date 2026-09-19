import Foundation

/// Collects live statistics for a connected tunnel.
///
/// Strategy, in order of preference:
/// 1. `wg show <iface> dump` via the privileged helper (signed builds) — full per-peer stats.
/// 2. `wg show <iface> dump` as the current user — works only if the control socket is readable.
/// 3. `netstat` — always works unprivileged, but only gives interface byte counters.
///
/// Installed routes always come from `netstat -rn`, which needs no privileges.
@MainActor
struct TunnelDetailsFetcher {
    /// Interfaces where the unprivileged `wg show` already failed with a permission error.
    /// Avoids spawning a doomed process on every refresh tick.
    private static var unprivilegedWGDenied: Set<String> = []

    static func fetch(for tunnel: Tunnel, interface: String) async throws -> TunnelDetails {
        let localIP = tunnel.config.interface.addresses.first ?? "—"
        let localHosts = Set(tunnel.config.interface.addresses.map { $0.split(separator: "/").first.map(String.init) ?? $0 })
        let installedRoutes = (try? await installedRoutes(for: interface, excluding: localHosts)) ?? []

        if let dump = await wireGuardDump(for: interface) {
            let parsed = parseDump(dump, config: tunnel.config)
            return TunnelDetails(
                interface: interface,
                source: .wireguard,
                fetchedAt: Date(),
                txBytes: parsed.peers.reduce(0) { $0 + $1.txBytes },
                rxBytes: parsed.peers.reduce(0) { $0 + $1.rxBytes },
                localIP: localIP,
                listenPort: parsed.listenPort,
                publicKey: parsed.publicKey,
                installedRoutes: installedRoutes,
                peers: parsed.peers
            )
        }

        let counters = try await interfaceCounters(for: interface)
        let peers = tunnel.config.peers.map { peer in
            TunnelDetails.PeerStats(
                publicKey: peer.publicKey,
                endpoint: peer.endpoint,
                allowedIPs: peer.allowedIPs,
                latestHandshake: nil,
                rxBytes: 0,
                txBytes: 0,
                persistentKeepalive: peer.persistentKeepalive
            )
        }
        return TunnelDetails(
            interface: interface,
            source: .system,
            fetchedAt: Date(),
            txBytes: counters.tx,
            rxBytes: counters.rx,
            localIP: localIP,
            listenPort: tunnel.config.interface.listenPort,
            publicKey: nil,
            installedRoutes: installedRoutes,
            peers: peers
        )
    }

    // MARK: - wg show dump

    private static func wireGuardDump(for interface: String) async -> String? {
        if let dump = try? await HelperManager.shared.tunnelStats(interface: interface) {
            return dump
        }

        guard !unprivilegedWGDenied.contains(interface),
              let wg = try? await WireGuardPaths.findExecutable("wg") else { return nil }

        do {
            return try await ShellRunner.run(wg, arguments: ["show", interface, "dump"])
        } catch ShellError.nonZeroExit(_, let stderr) where stderr.localizedCaseInsensitiveContains("permission denied") {
            unprivilegedWGDenied.insert(interface)
            return nil
        } catch {
            return nil
        }
    }

    private struct ParsedDump {
        var publicKey: String?
        var listenPort: Int?
        var peers: [TunnelDetails.PeerStats] = []
    }

    /// `wg show <iface> dump` output is tab-separated:
    /// line 1: private-key, public-key, listen-port, fwmark
    /// peers:  public-key, preshared-key, endpoint, allowed-ips, latest-handshake, rx, tx, keepalive
    private static func parseDump(_ dump: String, config: WireGuardConfig) -> ParsedDump {
        var result = ParsedDump()
        let lines = dump.split(separator: "\n").map { $0.components(separatedBy: "\t") }
        guard let header = lines.first else { return result }

        if header.count >= 3 {
            result.publicKey = header[1]
            result.listenPort = Int(header[2])
        }

        for fields in lines.dropFirst() where fields.count >= 8 {
            let handshake = TimeInterval(fields[4]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            let keepalive = fields[7] == "off" ? nil : Int(fields[7])
            let allowedIPs = fields[3] == "(none)" ? [] : fields[3].components(separatedBy: ",")
            result.peers.append(TunnelDetails.PeerStats(
                publicKey: fields[0],
                endpoint: fields[2] == "(none)" ? nil : fields[2],
                allowedIPs: allowedIPs,
                latestHandshake: handshake,
                rxBytes: UInt64(fields[5]) ?? 0,
                txBytes: UInt64(fields[6]) ?? 0,
                persistentKeepalive: keepalive
            ))
        }
        return result
    }

    // MARK: - netstat fallbacks

    /// Interface byte counters from `netstat -ibn -I <iface>`.
    /// Columns: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll — but the Address
    /// column is empty for utun interfaces, so index the trailing counters from the end of the row.
    private static func interfaceCounters(for interface: String) async throws -> (rx: UInt64, tx: UInt64) {
        let output = try await ShellRunner.run("/usr/sbin/netstat", arguments: ["-ibn", "-I", interface])
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // The <Link#N> row carries the totals; address rows repeat them with "-" for error columns.
            guard columns.count >= 10, columns[0] == interface, columns[2].hasPrefix("<Link") else { continue }
            let obytes = columns[columns.count - 2]
            let ibytes = columns[columns.count - 5]
            return (UInt64(ibytes) ?? 0, UInt64(obytes) ?? 0)
        }
        return (0, 0)
    }

    /// Destinations in the routing table whose outgoing interface is `interface`.
    /// `excluding` holds the tunnel's own addresses so its host route is not listed as something it routes.
    private static func installedRoutes(for interface: String, excluding: Set<String>) async throws -> [String] {
        let output = try await ShellRunner.run("/usr/sbin/netstat", arguments: ["-rn"])
        var routes: [String] = []
        var seen = Set<String>()
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 4, columns[3] == interface || columns.last == interface else { continue }
            let destination = expandAbbreviatedIPv4(columns[0])
            // Skip non-address rows ("default"), the interface's own host entry, and IPv6 link-local/multicast scope routes.
            guard destination.first?.isNumber == true || destination.contains(":") else { continue }
            guard !excluding.contains(destination) else { continue }
            guard !destination.hasPrefix("fe80:"), !destination.hasPrefix("ff0") else { continue }
            if seen.insert(destination).inserted {
                routes.append(destination)
            }
        }
        return routes
    }

    /// `netstat -rn` abbreviates IPv4 networks ("10.60/16"); expand to the full dotted quad.
    private static func expandAbbreviatedIPv4(_ destination: String) -> String {
        guard !destination.contains(":") else { return destination }
        let parts = destination.split(separator: "/", maxSplits: 1).map(String.init)
        var octets = parts[0].split(separator: ".").map(String.init)
        guard octets.allSatisfy({ Int($0) != nil }), !octets.isEmpty, octets.count <= 4 else { return destination }
        while octets.count < 4 { octets.append("0") }
        let address = octets.joined(separator: ".")
        return parts.count == 2 ? "\(address)/\(parts[1])" : address
    }
}

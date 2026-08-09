import Foundation

struct TunnelDetailsFetcher {
    static func fetch(for tunnel: Tunnel, interface: String) async throws -> TunnelDetails {
        let wg = try await WireGuardPaths.findExecutable("wg")
        let output = try await ShellRunner.run(wg, arguments: ["show", interface])
        let (rxBytes, txBytes) = parseTransfer(from: output)

        let localIP = tunnel.config.interface.addresses.first ?? "—"
        let routes = tunnel.config.peers.flatMap(\.allowedIPs)

        return TunnelDetails(
            txBytes: txBytes,
            rxBytes: rxBytes,
            localIP: localIP,
            routes: routes
        )
    }

    private static func parseTransfer(from output: String) -> (rx: UInt64, tx: UInt64) {
        guard let line = output.split(separator: "\n").first(where: { $0.contains("transfer:") }) else {
            return (0, 0)
        }

        let trimmed = line
            .replacingOccurrences(of: "transfer:", with: "")
            .trimmingCharacters(in: .whitespaces)

        let parts = trimmed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let rx = parseByteString(parts.first)
        let tx = parseByteString(parts.last)
        return (rx, tx)
    }

    private static func parseByteString(_ string: String?) -> UInt64 {
        guard let string = string else { return 0 }
        let cleaned = string
            .replacingOccurrences(of: "received", with: "")
            .replacingOccurrences(of: "sent", with: "")
            .trimmingCharacters(in: .whitespaces)

        let components = cleaned.split(separator: " ").map { String($0) }
        guard components.count == 2,
              let value = Double(components[0]) else { return 0 }

        let multiplier: Double
        switch components[1] {
        case "B": multiplier = 1
        case "KiB": multiplier = 1024
        case "MiB": multiplier = 1024 * 1024
        case "GiB": multiplier = 1024 * 1024 * 1024
        case "TiB": multiplier = 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }

        return UInt64(value * multiplier)
    }
}

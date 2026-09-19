import Foundation

struct WireGuardConfig: Equatable {
    struct InterfaceSection: Equatable {
        var privateKey: String?
        var addresses: [String] = []
        var dns: [String] = []
        var listenPort: Int?
        var mtu: Int?
    }

    struct PeerSection: Equatable {
        var publicKey: String = ""
        var presharedKey: String?
        var allowedIPs: [String] = []
        var endpoint: String?
        var persistentKeepalive: Int?
    }

    var interface: InterfaceSection
    var peers: [PeerSection]

    /// Every AllowedIPs entry across all peers, in config order, without duplicates.
    var allowedIPs: [String] {
        var seen = Set<String>()
        return peers.flatMap(\.allowedIPs).filter { seen.insert($0).inserted }
    }

    /// True when the config routes all IPv4 or IPv6 traffic through the tunnel.
    var routesAllTraffic: Bool {
        allowedIPs.contains { $0 == "0.0.0.0/0" || $0 == "::/0" }
    }

    /// Short human summary of what the tunnel routes, e.g. "All traffic" or "10.0.0.0/24, 10.1.0.0/16".
    var routeSummary: String {
        if allowedIPs.isEmpty { return "No routes" }
        if routesAllTraffic { return "All traffic" }
        return allowedIPs.joined(separator: ", ")
    }
}

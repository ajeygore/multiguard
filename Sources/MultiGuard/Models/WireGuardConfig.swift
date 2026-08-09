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
}

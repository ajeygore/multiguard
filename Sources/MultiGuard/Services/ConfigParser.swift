import Foundation

enum ConfigParserError: Error, LocalizedError {
    case missingPrivateKey

    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            return "WireGuard config is missing PrivateKey under [Interface]."
        }
    }
}

struct ConfigParser {
    static func parse(_ content: String) throws -> WireGuardConfig {
        var interface = WireGuardConfig.InterfaceSection()
        var peers: [WireGuardConfig.PeerSection] = []
        var currentPeer: WireGuardConfig.PeerSection?

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            if line == "[Interface]" {
                if let peer = currentPeer {
                    peers.append(peer)
                    currentPeer = nil
                }
            } else if line == "[Peer]" {
                if let peer = currentPeer {
                    peers.append(peer)
                }
                currentPeer = WireGuardConfig.PeerSection()
            } else if currentPeer != nil {
                guard let (key, value) = parseKeyValue(line) else { continue }
                switch key {
                case "PublicKey": currentPeer?.publicKey = value
                case "PresharedKey": currentPeer?.presharedKey = value
                case "AllowedIPs":
                    currentPeer?.allowedIPs = splitCommaSeparated(value)
                case "Endpoint": currentPeer?.endpoint = value
                case "PersistentKeepalive":
                    currentPeer?.persistentKeepalive = Int(value)
                default: break
                }
            } else {
                guard let (key, value) = parseKeyValue(line) else { continue }
                switch key {
                case "PrivateKey": interface.privateKey = value
                case "Address":
                    interface.addresses = splitCommaSeparated(value)
                case "DNS":
                    interface.dns = splitCommaSeparated(value)
                case "ListenPort": interface.listenPort = Int(value)
                case "MTU": interface.mtu = Int(value)
                default: break
                }
            }
        }

        if let peer = currentPeer {
            peers.append(peer)
        }

        guard interface.privateKey != nil else {
            throw ConfigParserError.missingPrivateKey
        }

        return WireGuardConfig(interface: interface, peers: peers)
    }

    private static func parseKeyValue(_ line: String) -> (String, String)? {
        let parts = line.split(separator: "=", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private static func splitCommaSeparated(_ value: String) -> [String] {
        return value.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

import Foundation

struct PersistedTunnel: Codable {
    let id: UUID
    let name: String
    var bindInterface: String?
}

actor TunnelStore {
    static let shared = TunnelStore()

    private var appSupportDirectory: URL {
        let fm = FileManager.default
        let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MultiGuard", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var configsDirectory: URL {
        let url = appSupportDirectory.appendingPathComponent("Configs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var storageURL: URL {
        appSupportDirectory.appendingPathComponent("tunnels.json")
    }

    func configURL(for id: UUID) -> URL {
        // wg-quick on macOS requires the config basename (minus .conf) to be a valid
        // interface name: <= 15 chars, no hyphens. UUIDs contain hyphens, so derive a
        // short alphanumeric name: mg_<12 hex chars> = 15 chars total.
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "")
        let interfaceName = "mg_" + String(hex.prefix(12))
        return configsDirectory.appendingPathComponent("\(interfaceName).conf")
    }

    private func legacyConfigURL(for id: UUID) -> URL {
        configsDirectory.appendingPathComponent("\(id.uuidString).conf")
    }

    /// Import a config by copying its content into the app support directory.
    /// The original file is no longer needed after this returns.
    func importTunnel(name: String, content: String, bindInterface: String? = nil) throws -> Tunnel {
        let id = UUID()
        let configURL = configURL(for: id)
        try content.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ConfigParser.parse(content)
        return Tunnel(id: id, name: name, fileURL: configURL, config: config, bindInterface: bindInterface)
    }

    func save(_ tunnels: [Tunnel]) async throws {
        let persisted = tunnels.map { tunnel in
            PersistedTunnel(id: tunnel.id, name: tunnel.name, bindInterface: tunnel.bindInterface)
        }
        let data = try JSONEncoder().encode(persisted)
        try data.write(to: storageURL, options: .atomic)
    }

    func load() async -> [Tunnel] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        guard let persisted = try? JSONDecoder().decode([PersistedTunnel].self, from: data) else { return [] }

        var tunnels: [Tunnel] = []
        for pt in persisted {
            let configURL = configURL(for: pt.id)
            let legacyURL = legacyConfigURL(for: pt.id)

            // Migrate configs saved with the old hyphenated-UUID filename.
            if !FileManager.default.fileExists(atPath: configURL.path),
               FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.moveItem(at: legacyURL, to: configURL)
            }

            guard let content = try? String(contentsOf: configURL),
                  let config = try? ConfigParser.parse(content) else { continue }

            let tunnel = Tunnel(
                id: pt.id,
                name: pt.name,
                fileURL: configURL,
                config: config,
                bindInterface: pt.bindInterface
            )
            tunnels.append(tunnel)
        }
        return tunnels
    }

    func delete(_ tunnel: Tunnel) async throws {
        let configURL = configURL(for: tunnel.id)
        try? FileManager.default.removeItem(at: configURL)
    }

    func deleteAll() async throws {
        try? FileManager.default.removeItem(at: appSupportDirectory)
    }
}

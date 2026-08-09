import Foundation

enum TunnelStatus: Equatable {
    case disconnected
    case connecting
    case connected(interface: String)
    case disconnecting
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isDisconnectedOrFailed: Bool {
        if case .disconnected = self { return true }
        if case .failed = self { return true }
        return false
    }
}

struct Tunnel: Identifiable, Equatable {
    let id: UUID
    var name: String
    var fileURL: URL
    var config: WireGuardConfig
    var status: TunnelStatus = .disconnected
    var bindInterface: String?
    var details: TunnelDetails?
}

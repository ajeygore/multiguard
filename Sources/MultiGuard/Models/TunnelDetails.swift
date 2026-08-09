import Foundation

struct TunnelDetails: Equatable {
    let txBytes: UInt64
    let rxBytes: UInt64
    let localIP: String
    let routes: [String]

    var formattedTX: String {
        formatBytes(txBytes)
    }

    var formattedRX: String {
        formatBytes(rxBytes)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.2f %@", value, units[index])
    }
}

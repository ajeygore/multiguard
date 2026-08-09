import SwiftUI

enum Theme {
    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let cardBackground = Color(NSColor.controlBackgroundColor)
    static let windowBackground = Color(NSColor.windowBackgroundColor)
    
    enum Status {
        static func color(for status: TunnelStatus) -> Color {
            switch status {
            case .connected: return Theme.success
            case .connecting, .disconnecting: return Theme.warning
            case .failed: return Theme.error
            case .disconnected: return .secondary
            }
        }
        
        static func icon(for status: TunnelStatus) -> String {
            switch status {
            case .connected: return "checkmark.shield.fill"
            case .connecting: return "shield.lefthalf.filled"
            case .disconnecting: return "shield.slash"
            case .failed: return "exclamationmark.shield"
            case .disconnected: return "shield"
            }
        }
    }
}

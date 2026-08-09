import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

@MainActor
final class AppearanceController: ObservableObject {
    static let shared = AppearanceController()

    @Published var current: AppAppearance = .system {
        didSet { apply() }
    }

    private init() {
        apply()
    }

    func cycle() {
        switch current {
        case .system: current = .light
        case .light: current = .dark
        case .dark: current = .system
        }
    }

    private func apply() {
        switch current {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

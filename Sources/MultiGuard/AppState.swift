import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    let viewModel = TunnelListViewModel()

    private init() {
        Task {
            await viewModel.loadPersistedTunnels()
        }
    }
}

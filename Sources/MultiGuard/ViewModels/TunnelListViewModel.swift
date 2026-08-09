import Foundation

@MainActor
class TunnelListViewModel: ObservableObject {
    @Published var tunnels: [Tunnel] = []
    @Published var conflicts: [Conflict] = []
    @Published var importError: String?
    @Published var selectedTunnelIDs: Set<UUID> = []

    private let manager = TunnelManager()
    private var detailsRefreshTimer: Timer?

    var hasSelection: Bool {
        !selectedTunnelIDs.isEmpty
    }

    var allSelected: Bool {
        !tunnels.isEmpty && selectedTunnelIDs.count == tunnels.count
    }

    func loadPersistedTunnels() async {
        tunnels = await TunnelStore.shared.load()
        selectedTunnelIDs.removeAll()
        recomputeConflicts()
        startDetailsRefreshTimer()
    }

    func importConfig(from url: URL) {
        Task {
            do {
                let allowed = url.startAccessingSecurityScopedResource()
                defer { if allowed { url.stopAccessingSecurityScopedResource() } }

                let content = try String(contentsOf: url)
                let name = url.deletingPathExtension().lastPathComponent
                let tunnel = try await TunnelStore.shared.importTunnel(name: name, content: content)
                tunnels.append(tunnel)
                recomputeConflicts()
                importError = nil
                save()
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    func remove(_ tunnel: Tunnel) {
        Task {
            if case .connected = tunnel.status {
                try? await manager.disconnect(tunnel)
            }
            tunnels.removeAll { $0.id == tunnel.id }
            selectedTunnelIDs.remove(tunnel.id)
            recomputeConflicts()
            save()
            try? await TunnelStore.shared.delete(tunnel)
        }
    }

    func toggle(_ tunnel: Tunnel) {
        Task {
            await applyToggle(tunnel)
            recomputeConflicts()
        }
    }

    func selectAll() {
        selectedTunnelIDs = Set(tunnels.map(\.id))
    }

    func deselectAll() {
        selectedTunnelIDs.removeAll()
    }

    func setSelected(_ tunnel: Tunnel, isSelected: Bool) {
        if isSelected {
            selectedTunnelIDs.insert(tunnel.id)
        } else {
            selectedTunnelIDs.remove(tunnel.id)
        }
    }

    func connectSelected() {
        Task {
            let selected = tunnels.filter { tunnel in
                selectedTunnelIDs.contains(tunnel.id) && tunnel.status.isDisconnectedOrFailed
            }
            guard !selected.isEmpty else { return }

            for tunnel in selected {
                guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { continue }
                tunnels[index].status = .connecting
            }

            do {
                let interfaces = try await manager.connectTunnels(selected)
                for tunnel in selected {
                    guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { continue }
                    if let interface = interfaces[tunnel.id], interface != "unknown" {
                        tunnels[index].status = .connected(interface: interface)
                        if let details = try? await TunnelDetailsFetcher.fetch(for: tunnels[index], interface: interface) {
                            tunnels[index].details = details
                        }
                    } else {
                        tunnels[index].status = .failed("Could not discover tunnel interface")
                    }
                }
            } catch {
                for tunnel in selected {
                    guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { continue }
                    tunnels[index].status = .failed(error.localizedDescription)
                }
            }
            recomputeConflicts()
        }
    }

    func disconnectSelected() {
        Task {
            let selected = tunnels.filter { tunnel in
                selectedTunnelIDs.contains(tunnel.id) && tunnel.status.isConnected
            }
            guard !selected.isEmpty else { return }

            for tunnel in selected {
                guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { continue }
                tunnels[index].status = .disconnecting
            }

            do {
                try await manager.disconnectTunnels(selected)
                for tunnel in selected {
                    guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { continue }
                    tunnels[index].status = .disconnected
                    tunnels[index].details = nil
                }
            } catch {
                for tunnel in selected {
                    guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { continue }
                    tunnels[index].status = .failed(error.localizedDescription)
                }
            }
            recomputeConflicts()
        }
    }

    func setBindInterface(_ interface: String?, for tunnel: Tunnel) {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return }
        tunnels[index].bindInterface = interface
        save()
    }

    private func applyToggle(_ tunnel: Tunnel) async {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return }

        switch tunnel.status {
        case .disconnected, .failed:
            tunnels[index].status = .connecting
            do {
                let interface = try await manager.connect(tunnel)
                tunnels[index].status = .connected(interface: interface)
                if let details = try? await TunnelDetailsFetcher.fetch(for: tunnels[index], interface: interface) {
                    tunnels[index].details = details
                }
            } catch {
                tunnels[index].status = .failed(error.localizedDescription)
            }

        case .connected:
            tunnels[index].status = .disconnecting
            do {
                try await manager.disconnect(tunnel)
                tunnels[index].status = .disconnected
                tunnels[index].details = nil
            } catch {
                tunnels[index].status = .failed(error.localizedDescription)
            }

        default:
            break
        }
    }

    private func startDetailsRefreshTimer() {
        detailsRefreshTimer?.invalidate()
        detailsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshConnectedDetails()
            }
        }
    }

    private func refreshConnectedDetails() async {
        for index in tunnels.indices {
            if case .connected(let interface) = tunnels[index].status {
                if let details = try? await TunnelDetailsFetcher.fetch(for: tunnels[index], interface: interface) {
                    tunnels[index].details = details
                }
            }
        }
    }

    private func save() {
        Task {
            try? await TunnelStore.shared.save(tunnels)
        }
    }

    private func recomputeConflicts() {
        conflicts = ConflictDetector.conflicts(among: tunnels)
    }
}

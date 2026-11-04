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
        await adoptRunningTunnels()
        startDetailsRefreshTimer()
    }

    /// Mark tunnels that are already up on the system (left over from a previous session) as connected.
    private func adoptRunningTunnels() async {
        let running = await manager.runningInterfaces(for: tunnels)
        for (id, interface) in running {
            guard let index = tunnels.firstIndex(where: { $0.id == id }) else { continue }
            tunnels[index].status = .connected(interface: interface)
            if let details = try? await TunnelDetailsFetcher.fetch(for: tunnels[index], interface: interface) {
                tunnels[index].details = details
            }
        }
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

            let failures = await manager.disconnectTunnels(selected)
            for tunnel in selected {
                guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { continue }
                if let message = failures[tunnel.id] {
                    tunnels[index].status = .failed(message)
                } else {
                    tunnels[index].status = .disconnected
                    tunnels[index].details = nil
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
        let live = await manager.liveInterfaces()
        await adoptStrayTunnels(live: live)
        var dropped: [Tunnel] = []
        for index in tunnels.indices {
            if case .connected(let interface) = tunnels[index].status {
                // The tunnel went away without us (wireguard-go exited, typically around sleep/wake).
                if let live, !live.contains(interface) {
                    tunnels[index].status = .connecting
                    tunnels[index].details = nil
                    dropped.append(tunnels[index])
                    continue
                }
                if let details = try? await TunnelDetailsFetcher.fetch(for: tunnels[index], interface: interface) {
                    tunnels[index].details = details.withRates(since: tunnels[index].details)
                }
            }
        }
        if !dropped.isEmpty {
            Task { await reconnectDropped(dropped) }
        }
    }

    /// A tunnel shown as disconnected or failed while its interface is in fact up (e.g. a connect
    /// that reported an error after wg-quick had already succeeded) is marked connected again.
    private func adoptStrayTunnels(live: Set<String>?) async {
        guard let live, !live.isEmpty,
              tunnels.contains(where: { $0.status.isDisconnectedOrFailed }) else { return }
        let candidates = tunnels.filter { $0.status.isDisconnectedOrFailed }
        let running = await manager.runningInterfaces(for: candidates)
        for (id, interface) in running {
            // Re-check: the status may have changed while the interfaces were being read.
            guard let index = tunnels.firstIndex(where: { $0.id == id }),
                  tunnels[index].status.isDisconnectedOrFailed else { continue }
            tunnels[index].status = .connected(interface: interface)
            tunnels[index].details = try? await TunnelDetailsFetcher.fetch(for: tunnels[index], interface: interface)
        }
        if !running.isEmpty { recomputeConflicts() }
    }

    /// One automatic attempt, under a single admin prompt, once the network is back. A failed or
    /// cancelled attempt leaves the tunnels failed for the user to retry: no prompt loops.
    private func reconnectDropped(_ dropped: [Tunnel]) async {
        await manager.waitForDefaultRoute(timeout: 30)
        var interfaces: [UUID: String] = [:]
        let failure: String
        do {
            interfaces = try await manager.reconnect(dropped)
            failure = "Tunnel went down and could not be reconnected"
        } catch ShellError.cancelled {
            failure = "Tunnel went down; reconnect cancelled"
        } catch {
            failure = error.localizedDescription
        }
        for tunnel in dropped {
            guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }),
                  tunnels[index].status == .connecting else { continue }
            if let interface = interfaces[tunnel.id] {
                tunnels[index].status = .connected(interface: interface)
                tunnels[index].details = try? await TunnelDetailsFetcher.fetch(for: tunnels[index], interface: interface)
            } else {
                tunnels[index].status = .failed(failure)
            }
        }
        recomputeConflicts()
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

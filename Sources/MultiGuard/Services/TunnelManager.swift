import Foundation

actor TunnelManager {
    private var activeInterfaces: [UUID: String] = [:]

    func connect(_ tunnel: Tunnel) async throws -> String {
        do {
            let interface = try await HelperManager.shared.connectTunnel(configPath: tunnel.fileURL.path)
            activeInterfaces[tunnel.id] = interface
            return interface
        } catch {
            do {
                return try await fallbackConnect(tunnel)
            } catch {
                // The tunnel is already up (e.g. from a previous app session): adopt it instead of failing.
                if let interface = Self.existingInterface(from: error) {
                    activeInterfaces[tunnel.id] = interface
                    return interface
                }
                throw error
            }
        }
    }

    /// Tunnels that are already up on the system, keyed by tunnel id, discovered by matching each
    /// `utun` interface's address against the configs. Works without privileges (`wg show interfaces`
    /// and `ifconfig` are world-readable) so the app can recover state after a restart.
    func runningInterfaces(for tunnels: [Tunnel]) async -> [UUID: String] {
        guard let wg = try? await WireGuardPaths.findExecutable("wg"),
              let output = try? await ShellRunner.run(wg, arguments: ["show", "interfaces"]) else { return [:] }
        let interfaces = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var result: [UUID: String] = [:]
        for interface in interfaces {
            guard let ifconfig = try? await ShellRunner.run("/sbin/ifconfig", arguments: [interface]) else { continue }
            let addresses = Set(Self.parseAddresses(fromIfconfig: ifconfig))
            guard !addresses.isEmpty else { continue }
            for tunnel in tunnels where result[tunnel.id] == nil {
                let configured = tunnel.config.interface.addresses.map { $0.split(separator: "/").first.map(String.init) ?? $0 }
                if configured.contains(where: addresses.contains) {
                    result[tunnel.id] = interface
                    activeInterfaces[tunnel.id] = interface
                    break
                }
            }
        }
        return result
    }

    /// wg-quick reports "`name' already exists as `utunN'" when the interface is still up.
    private static func existingInterface(from error: Error) -> String? {
        let message = error.localizedDescription
        guard let range = message.range(of: "already exists as `") else { return nil }
        let rest = message[range.upperBound...]
        guard let end = rest.firstIndex(of: "'") else { return nil }
        let name = String(rest[..<end])
        return name.isEmpty ? nil : name
    }

    /// `inet 10.0.0.2 --> 10.0.0.2 netmask …` / `inet6 fd00::2 prefixlen 64` lines from `ifconfig`.
    private static func parseAddresses(fromIfconfig output: String) -> [String] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard parts.count >= 2, parts[0] == "inet" || parts[0] == "inet6" else { return nil }
            // Strip an IPv6 zone suffix such as fe80::1%utun6.
            return parts[1].split(separator: "%").first.map(String.init)
        }
    }

    func disconnect(_ tunnel: Tunnel) async throws {
        let interface = activeInterfaces[tunnel.id]
        do {
            try await HelperManager.shared.disconnectTunnel(configPath: tunnel.fileURL.path)
        } catch {
            do {
                try await fallbackDisconnect(tunnel)
            } catch let error where Self.isAlreadyDown(error) {
                // The tunnel died on its own (wireguard-go exited); down is the state we wanted.
            }
        }
        activeInterfaces.removeValue(forKey: tunnel.id)
        if let interface { await waitForRemoval(of: interface) }
    }

    /// Interfaces with a live WireGuard control socket. `nil` when `wg` can't be run, so callers
    /// don't mistake a tooling problem for every tunnel having gone down.
    func liveInterfaces() async -> Set<String>? {
        guard let wg = try? await WireGuardPaths.findExecutable("wg"),
              let output = try? await ShellRunner.run(wg, arguments: ["show", "interfaces"]) else { return nil }
        return Set(output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
    }

    /// wg-quick reports "`name' is not a WireGuard interface" when there is nothing left to bring down.
    private static func isAlreadyDown(_ error: Error) -> Bool {
        error.localizedDescription.contains("is not a WireGuard interface")
    }

    /// `wg-quick down` only deletes the control socket; wireguard-go and wg-quick's route monitor
    /// then tear the utun down asynchronously. Reconnecting before that finishes can hand the new
    /// tunnel the same utun name, which the old monitor then mistakes for its own and strips of
    /// routes and DNS on exit. Wait (briefly) for the interface to really disappear.
    private func waitForRemoval(of interface: String) async {
        for _ in 0..<15 {
            if (try? await ShellRunner.run("/sbin/ifconfig", arguments: [interface])) == nil { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    func connectTunnels(_ tunnels: [Tunnel]) async throws -> [UUID: String] {
        var interfaces: [UUID: String] = [:]
        for tunnel in tunnels {
            do {
                let interface = try await HelperManager.shared.connectTunnel(configPath: tunnel.fileURL.path)
                interfaces[tunnel.id] = interface
                activeInterfaces[tunnel.id] = interface
            } catch {
                do {
                    let interface = try await fallbackConnect(tunnel)
                    interfaces[tunnel.id] = interface
                    activeInterfaces[tunnel.id] = interface
                } catch {
                    let interface = Self.existingInterface(from: error) ?? "unknown"
                    interfaces[tunnel.id] = interface
                    if interface != "unknown" { activeInterfaces[tunnel.id] = interface }
                }
            }
        }
        return interfaces
    }

    /// Bring dropped tunnels back up under a single privilege prompt (one prompt per tunnel would
    /// be a barrage after every wake). Returns the interfaces of the tunnels that came up.
    func reconnect(_ tunnels: [Tunnel]) async throws -> [UUID: String] {
        if await HelperManager.shared.isInstalled {
            return try await connectTunnels(tunnels).filter { $0.value != "unknown" }
        }
        let wgQuick = try await WireGuardPaths.findExecutable("wg-quick")
        let bash = try await BashPaths.findBash4()
        // Each tunnel in its own subshell so one failure doesn't stop the rest, with one retry for
        // the window after wake where the endpoint's DNS name doesn't resolve yet. Which tunnels
        // actually came up is read back afterwards rather than parsed from the output.
        let script = try tunnels.map { tunnel in
            let up = try Self.upScript(for: tunnel, bash: bash, wgQuick: wgQuick)
            return "( (\(up)) || (sleep 3; \(up)) )"
        }.joined(separator: "; ") + "; exit 0"
        let names = tunnels.map(\.name).joined(separator: ", ")
        _ = try await ShellRunner.runAsAdmin(script: script, prompt: "MultiGuard needs to reconnect \(names).")
        return await runningInterfaces(for: tunnels)
    }

    /// After wake the tunnel can drop before Wi-Fi is back; reconnecting then just fails.
    func waitForDefaultRoute(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await ShellRunner.run("/sbin/route", arguments: ["-n", "get", "default"])) != nil { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Returns the tunnels that failed to disconnect, with the reason.
    func disconnectTunnels(_ tunnels: [Tunnel]) async -> [UUID: String] {
        var failures: [UUID: String] = [:]
        for tunnel in tunnels {
            do {
                try await disconnect(tunnel)
            } catch {
                failures[tunnel.id] = error.localizedDescription
            }
        }
        return failures
    }

    // MARK: - Fallback for unsigned / development builds

    private func fallbackConnect(_ tunnel: Tunnel) async throws -> String {
        let wgQuick = try await WireGuardPaths.findExecutable("wg-quick")
        let wg = try await WireGuardPaths.findExecutable("wg")
        let bash = try await BashPaths.findBash4()

        _ = try await ShellRunner.runAsAdmin(script: try Self.upScript(for: tunnel, bash: bash, wgQuick: wgQuick))

        let interface = try await discoverInterface(for: tunnel.config, wgPath: wg)
        return interface
    }

    private func fallbackDisconnect(_ tunnel: Tunnel) async throws {
        let wgQuick = try await WireGuardPaths.findExecutable("wg-quick")
        let bash = try await BashPaths.findBash4()
        _ = try await ShellRunner.runAsAdmin(command: bash, arguments: [wgQuick, "down", tunnel.fileURL.path], logURL: Self.logURL(for: tunnel))
    }

    /// The root shell script that brings `tunnel` up as a launchd job of its own.
    ///
    /// Run straight from `do shell script … with administrator privileges`, wireguard-go and
    /// wg-quick's route monitor stay in the process group of the system's authtrampoline job, and
    /// launchd kills that group when memory pressure idle-exits the trampoline (~13 minutes in),
    /// taking every tunnel down at once. Our own job with AbandonProcessGroup leaves them running
    /// after `wg-quick up` returns. The script waits for that exit and mirrors its status and error
    /// text, so callers see the same result as running wg-quick directly.
    private static func upScript(for tunnel: Tunnel, bash: String, wgQuick: String) throws -> String {
        let label = "com.multiguard.tunnel." + tunnel.fileURL.deletingPathExtension().lastPathComponent
        let log = logURL(for: tunnel).path
        let rcPath = "/var/run/multiguard/\(label).rc"
        let job: [String: Any] = [
            "Label": label,
            // launchd reports no exit code while wg-quick's route monitor is alive in the job, so
            // the wrapper records wg-quick's own status in a file the script polls instead.
            "ProgramArguments": ["/bin/sh", "-c", "\"$@\"; echo $? >" + ShellRunner.escapeForShell(rcPath),
                                 "sh", bash, wgQuick, "up", tunnel.fileURL.path],
            // wireguard-go only logs (to the job's stdout) when LOG_LEVEL is set.
            "EnvironmentVariables": ["LOG_LEVEL": "error"],
            "StandardOutPath": log,
            "StandardErrorPath": log,
            "RunAtLoad": true,
            "KeepAlive": false,
            "AbandonProcessGroup": true,
            "ProcessType": "Interactive",
        ]
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(label + ".plist")
        try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: staged)

        // launchd only loads root-owned plists, hence the copy. The status file appears once
        // wg-quick has exited; give it a minute (endpoint DNS can be slow right after wake).
        let q = ShellRunner.escapeForShell
        return """
        L=\(q(label)); P=\(q("/var/run/multiguard/\(label).plist")); LOG=\(q(log)); RC=\(q(rcPath)); \
        mkdir -p /var/run/multiguard && install -o root -g wheel -m 644 \(q(staged.path)) "$P" || exit 1; \
        launchctl bootout system/$L 2>/dev/null; rm -f "$RC"; echo "== $(date '+%F %T') up" >>"$LOG"; \
        launchctl bootstrap system "$P" || exit 1; \
        rc=; for i in $(seq 300); do \
        [ -s "$RC" ] && { rc=$(cat "$RC"); break; }; sleep 0.2; done; \
        launchctl bootout system/$L 2>/dev/null; rm -f "$RC"; \
        [ "$rc" = 0 ] || { tail -n 3 "$LOG" >&2; exit 1; }
        """
    }

    /// `~/Library/Logs/MultiGuard/<interface name>.log`: wg-quick output plus wireguard-go errors,
    /// so a tunnel that dies on its own leaves a reason behind.
    private static func logURL(for tunnel: Tunnel) -> URL {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MultiGuard", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(tunnel.fileURL.deletingPathExtension().lastPathComponent + ".log")
    }

    /// The interface wg-quick just created for `config`. Matched by interface address, which is
    /// world-readable; `wg show <iface>` needs root, so peer keys can't be relied on. Guessing
    /// (e.g. the last interface) would record the wrong utun when several tunnels are up, and the
    /// app would later treat the tunnel as dropped when that other interface goes away.
    private func discoverInterface(for config: WireGuardConfig, wgPath: String) async throws -> String {
        let output = try await ShellRunner.run(wgPath, arguments: ["show", "interfaces"])
        let interfaces = output
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let configured = Set(config.interface.addresses.map { $0.split(separator: "/").first.map(String.init) ?? $0 })

        for interface in interfaces {
            if let ifconfig = try? await ShellRunner.run("/sbin/ifconfig", arguments: [interface]),
               !configured.isDisjoint(with: Self.parseAddresses(fromIfconfig: ifconfig)) {
                return interface
            }
            // Readable only when the control socket is (privileged helper or root).
            if let dump = try? await ShellRunner.run(wgPath, arguments: ["show", interface]),
               config.peers.contains(where: { dump.contains($0.publicKey) }) {
                return interface
            }
        }
        throw ShellError.failed("Could not determine which interface the tunnel is using")
    }
}

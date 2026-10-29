---
title: MultiGuard Architecture
tags: [multiguard, architecture, swiftui, xpc]
summary: Internal structure of the MultiGuard app and its privileged helper.
---

# MultiGuard Architecture

## Targets

| Target | Type | Role |
|--------|------|------|
| `MultiGuard` | SwiftUI executable | Main app UI and business logic. |
| `MultiGuardHelper` | XPC command-line tool | Privileged helper that runs `wg-quick` as root. |

## App components

- **`ConfigParser`** — Parses WireGuard `.conf` files into `WireGuardConfig`.
- **`ConflictDetector`** — Compares `Address` and `AllowedIPs` CIDRs across configs to detect overlaps.
- **`TunnelStore`** — Copies imported configs to `~/Library/Application Support/MultiGuard/Configs/` and persists tunnel metadata.
- **`TunnelManager`** — Routes connect/disconnect requests to the privileged helper, falling back to `osascript` for unsigned dev builds.
- **`HelperManager`** — Installs the helper via `SMAppService` and manages the XPC connection.
- **`TunnelDetailsFetcher`** — Queries `wg show <interface>` for live RX/TX stats.
- **`ContentView` / `MenuBarView`** — SwiftUI frontends.

## Privileged helper

The helper (`com.multiguard.helper`) is registered once via `SMAppService.daemon`. Its launchd plist (`Resources/com.multiguard.helper.plist`) uses `BundleProgram` = `Contents/Library/LaunchServices/MultiGuardHelper`, so launchd runs the binary straight out of the app bundle — moving or deleting `MultiGuard.app` breaks the helper.

- **Client check:** the helper reads the Team ID from its *own* signature and only accepts XPC clients matching `identifier "com.multiguard.app" and anchor apple generic and certificate leaf[subject.OU] = "<team>"`. No Team ID is compiled in; an ad-hoc helper (no team) rejects everyone.
- **Approval:** the first registration needs the user to allow the background item in *System Settings → General → Login Items & Extensions*; the app opens that pane when `SMAppService` reports `.requiresApproval`. Afterwards `wg-quick up/down` runs without prompts.
- **Concurrency:** NSXPC delivers a connection's messages one at a time, so every request runs on a global queue. A stuck `wg show <iface> dump` (blocked on a hung wireguard-go) no longer queues a disconnect behind it.
- **Timeouts:** every child process is killed after a limit (`wg show … dump` 5 s, `wg-quick` 30 s, others 10 s): SIGTERM, then SIGKILL after 2 s. Output is collected via `readabilityHandler`, never read to EOF, because `wg-quick up` leaves wireguard-go and its route monitor holding the pipes. Each handler removes itself when it sees empty data (EOF); otherwise it fires in a tight loop.
- **Errors:** replies carry an `NSError` with an explicit `NSLocalizedDescriptionKey`; a Swift `LocalizedError` loses its message across XPC.
- **PATH:** launchd starts the helper with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`; the helper prepends `/opt/homebrew/bin:/usr/local/bin` for the processes it spawns so `wg-quick` finds `wg` and Bash 4+.

### App side (`HelperManager`)

- Ad-hoc builds (no Team ID in the app's own signature) never register the helper and unregister any stale registration, then go straight to the `osascript` fallback.
- Every XPC call goes through one `call(timeout:)` path: `remoteObjectProxyWithErrorHandler` plus a timeout (ping 3 s, stats 8 s, connect/disconnect 50 s). On timeout or connection error the cached connection is dropped.
- `TunnelManager` falls back to the `osascript` prompt only when the helper is *unavailable*. If the helper ran `wg-quick` and it failed or timed out, the error is shown instead of prompting for a password that would end the same way.
- Disconnecting a tunnel whose wireguard-go already died (`… is not a WireGuard interface`) counts as success.
- The 2 s stats refresh skips a tick while the previous one is still running, and marks a tunnel *failed — "Tunnel is no longer running"* when its interface disappears from `wg show interfaces`.

## Tunnel lifetime

Tunnels are owned by the system (`wg-quick` creates the `utun` device), not by the app. Quitting MultiGuard leaves them up; on launch `TunnelManager.runningInterfaces` adopts them by matching each `utun` address against the configs.

## Multiple interfaces

Each tunnel gets a unique config file name (`mg_<12-hex-chars>.conf`). `wg-quick up <file>` creates a separate `utun` device per tunnel, so traffic is routed independently rather than forcing all peers through one shared interface.

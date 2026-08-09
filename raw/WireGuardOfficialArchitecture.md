# How the official WireGuard macOS app is built

Source repository: [git.zx2c4.com/wireguard-apple](https://git.zx2c4.com/wireguard-apple/about/)  
GitHub mirror: [WireGuard/wireguard-apple](https://github.com/WireGuard/wireguard-apple)

## Build system

- Native **Xcode project** (`WireGuard.xcodeproj`), not Electron or web-based.
- Main language: **Swift** for UI and glue.
- Requires **Go** to compile the `wireguard-go` backend.
- Requires **swiftlint** for linting.
- Requires an **Apple Developer Team ID** for code signing the Network Extension.

High-level build steps from the README:

```bash
git clone https://git.zx2c4.com/wireguard-apple
cd wireguard-apple
cp Sources/WireGuardApp/Config/Developer.xcconfig.template \
   Sources/WireGuardApp/Config/Developer.xcconfig
# edit Developer.xcconfig with your team ID
brew install swiftlint go
open WireGuard.xcodeproj
```

## Architecture

The app is split into two processes:

1. **Main app** — native Swift/AppKit/SwiftUI UI for importing configs and toggling tunnels.
2. **Network Extension** — a `NEPacketTunnelProvider` that owns the actual VPN interface.

They communicate through the standard Network Extension APIs (`NETunnelProviderManager`, `NETunnelProviderSession`, IPC app messages).

### Key components

| Component | Role |
|-----------|------|
| `WireGuardKit` | Swift package/framework inside the repo. Parses configs, resolves endpoints, generates network settings. |
| `WireGuardAdapter` | Bridges `NEPacketTunnelProvider` to the Go backend. Opens the `utun` fd, calls `setTunnelNetworkSettings(_:)`, starts `wireguard-go`. |
| `PacketTunnelProvider` | `NEPacketTunnelProvider` subclass. Entry point for the system extension. |
| `WireGuardKitGo` | External Build System target that compiles `wireguard-go` (Go) into a library. |
| `WireGuardKitC` | C helper functions used by Swift/Go bridge. |

### Data flow

```
Main App  →  NETunnelProviderManager
                  ↓
       PacketTunnelProvider (NEPacketTunnelProvider)
                  ↓
       WireGuardAdapter
                  ↓
    ┌─────────────────────────────┐
    │  Open utun file descriptor  │
    │  setTunnelNetworkSettings() │
    │  wgTurnOn()                 │
    └─────────────────────────────┘
                  ↓
         wireguard-go (Go backend)
```

### Important implementation details

- `WireGuardAdapter` finds the `utun` fd by scanning file descriptors 0…1024 and matching `com.apple.net.utun_control` ([source](https://git.zx2c4.com/wireguard-apple/plain/Sources/WireGuardKit/WireGuardAdapter.swift)).
- It uses `NWPathMonitor` to react to network changes and calls `wgBumpSockets` on macOS.
- DNS resolution happens before starting the backend; failures are reported back to the UI.
- The network extension target must be signed with a Network Extension entitlement.

## Trade-offs vs. our CLI-based MultiGuard

| Aspect | Official app | MultiGuard |
|--------|--------------|------------|
| Tunnel tech | `NEPacketTunnelProvider` + `wireguard-go` | `wg` / `wg-quick` CLI |
| Backend | Swift + Go | Swift only |
| Privileges | One-time system extension approval | `osascript` admin prompt per action |
| Routing | Native via NetworkExtension | Managed by `wg-quick` |
| Distribution | Mac App Store / notarized `.app` | Unsigned dev bundle |
| Complexity | High (entitlements, Go build, signing) | Low |
| Multi-tunnel | Official UI restricts it; extension can support it | Explicit multi-config design |

## When to follow the official approach

Use `NEPacketTunnelProvider` + `wireguard-go` if you need:
- A real system VPN toggle in **System Settings → VPN**
- On-demand rules
- App Store distribution
- A single privilege grant

Use the `wg-quick` CLI approach (MultiGuard) if you need:
- A quick prototype or internal tool
- Multiple simultaneous tunnels without fighting the official UI
- Minimal code signing / entitlements overhead

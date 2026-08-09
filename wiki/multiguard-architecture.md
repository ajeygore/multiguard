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

The helper (`com.multiguard.helper`) is installed once via `SMAppService`. It validates the main app’s code signature with `SecCodeCheckValidity` before accepting XPC connections. After the one-time system authorization dialog, all `wg-quick up/down` operations run without further prompts.

## Multiple interfaces

Each tunnel gets a unique config file name (`mg_<12-hex-chars>.conf`). `wg-quick up <file>` creates a separate `utun` device per tunnel, so traffic is routed independently rather than forcing all peers through one shared interface.

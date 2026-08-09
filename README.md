# MultiGuard

A native macOS app for managing **multiple WireGuard tunnels at the same time**.

Unlike the official WireGuard client, which is designed around a single active tunnel, MultiGuard lets you import several WireGuard configurations, detect address conflicts, and connect or disconnect them individually or in bulk. Each tunnel gets its own `utun` interface, so traffic is routed independently rather than forcing every peer through one shared interface.

> **Underlying tools:** MultiGuard is a frontend for the official [`wireguard-tools`](https://formulae.brew.sh/formula/wireguard-tools) (`wg` / `wg-quick`) command-line utilities. It does not reimplement the WireGuard protocol.

---

## Why MultiGuard?

- **Multiple simultaneous tunnels** — connect to several WireGuard endpoints at once, each on its own virtual interface.
- **Conflict detection** — automatically warns you when two configs use overlapping addresses or routes.
- **Native macOS UI** — built with SwiftUI, menu-bar integration, light/dark mode, and a clean card-based layout.
- **Bulk actions** — select any number of tunnels and connect/disconnect them together.
- **Persistent configs** — imported `.conf` files are copied locally, so you can delete the originals and still connect.
- **No Electron** — lightweight, native integration with macOS networking and CLI tools.

---

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ or the Swift command-line tools
- [Homebrew](https://brew.sh)
- `wireguard-tools` and Bash 4+:

```bash
brew install wireguard-tools bash
```

---

## Build and run

### Option 1: Open in Xcode

```bash
cd multiguard
open Package.swift
```

Then press **Cmd+R**.

### Option 2: Build from the terminal

```bash
cd multiguard
swift build
./scripts/build-app.sh
open MultiGuard.app
```

### Development vs. signed builds

For development, the build script ad-hoc signs the app. The privileged helper cannot be installed without an Apple Developer ID, so MultiGuard will fall back to the standard macOS administrator prompt when connecting or disconnecting tunnels.

To enable the one-time-authorization helper (no repeated prompts), sign with your Apple Developer Team ID:

```bash
DEVELOPER_ID=ABCD123456 ./scripts/build-app.sh
open MultiGuard.app
```

Replace `ABCD123456` with your actual Team ID. You can find it in the [Apple Developer portal](https://developer.apple.com) or by running:

```bash
security find-identity -v -p codesigning
```

For distribution, notarize the `.app` with `xcrun notarytool`.

---

## Usage

1. Click **Import** and select one or more WireGuard `.conf` files.
2. MultiGuard copies each config locally and immediately highlights any **address/routing conflicts**.
3. Select tunnels with the checkboxes and click **Connect** / **Disconnect**, or toggle a single tunnel from its card.
4. Once connected, each card shows live stats: **RX/TX bytes**, **local IP**, and **routes**.
5. Use the lock-shield menu-bar icon for quick connect/disconnect without opening the main window.

---

## Architecture

- **SwiftUI frontend** — `ContentView` and `MenuBarView`.
- **`ConfigParser`** — parses WireGuard `.conf` files.
- **`ConflictDetector`** — detects overlapping `Address` / `AllowedIPs` CIDRs across configs.
- **`TunnelStore`** — persists imported tunnels and copies config files into `~/Library/Application Support/MultiGuard/Configs/`.
- **`TunnelManager`** — talks to the privileged helper (or falls back to `osascript`) to run `wg-quick up/down`.
- **`MultiGuardHelper`** — XPC privileged helper tool that runs `wg`/`wg-quick` as root.

### How multiple tunnels work

MultiGuard gives every tunnel a unique interface name (e.g. `mg_550e8400e29b`) by writing each config to its own uniquely-named file and running `wg-quick up <file>`. WireGuard/macOS then assigns a separate `utun` device per tunnel, so routes and peers stay isolated instead of being forced through a single shared interface.

---

## Code signing and privileges

`wg-quick` needs root to create network interfaces and routes. MultiGuard uses Apple’s recommended `SMAppService` privileged-helper pattern for one-time authorization. The helper validates the main app’s code signature before accepting XPC connections.

Unsigned development builds fall back to the standard macOS administrator prompt.

---

## Regenerating the app icon

The icon is generated from `Resources/AppIcon.svg`:

```bash
./scripts/generate-icon.sh
./scripts/build-app.sh
```

---

## License

MIT

---
title: MultiGuard Design Decisions
tags: [multiguard, decisions]
summary: Key technical choices made while building MultiGuard.
---

# MultiGuard Design Decisions

## Native SwiftUI instead of Electron

Chosen because MultiGuard is a macOS-only system utility that shells out to CLI tools. SwiftUI is lighter, integrates cleanly with `Process` and `NSPasteboard`, and avoids bundling a Chromium runtime.

## `wg-quick` CLI instead of Network Extension

A Network Extension (`NEPacketTunnelProvider`) is the Apple-approved, App Store-friendly approach, but it requires entitlements, an Apple Developer account, and a Go build step for `wireguard-go`. Using `wg-quick` allowed a working prototype with minimal signing complexity.

## Privileged helper for production

For repeated connect/disconnect without password prompts, Apple recommends a privileged helper installed via `SMAppService`. MultiGuard implements this helper and falls back to `osascript` admin prompts when the app is unsigned.

## Unique interface per tunnel

Each imported config is copied to a uniquely-named file (`mg_<12-hex-chars>.conf`). `wg-quick` then creates a separate `utun` device per tunnel. This keeps routes and peers isolated instead of binding every peer to the same interface.

## Local config copies

Imported `.conf` content is copied into `~/Library/Application Support/MultiGuard/Configs/`. This lets users delete the original files and still connect, and ensures the stored path is stable for `wg-quick up/down`.

## Edit profiles as raw config text

Profiles used to be immutable: changing one meant deleting and re-importing it. The editor shows the full `.conf` text. Rejected: a form with one field per key — `ConfigParser` only models a subset of keys (no `PostUp`, `Table`, …), so a form would silently drop the rest; opening the file in an external editor — no validation and no way to handle a connected tunnel.

A connected tunnel is taken down **before** the file is overwritten, because `wg-quick down` reads the config for its `PreDown`/`PostDown` hooks and must see the version the tunnel was brought up with. A rename alone saves without reconnecting.

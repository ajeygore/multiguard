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

## Run each tunnel as its own launchd job (unsigned fallback)

Run directly from `osascript … with administrator privileges`, `wireguard-go` and wg-quick's route monitor stay in the process group of the system's `authtrampoline` job. launchd kills that group when memory pressure idle-exits the trampoline (about 13 minutes in), taking every tunnel down at once.

Each tunnel is now bootstrapped as `com.multiguard.tunnel.<name>` with `AbandonProcessGroup`, so the daemons outlive `wg-quick up`. Output goes to `~/Library/Logs/MultiGuard/<name>.log`.

**Rejected:** `nohup`/`setsid` (still in the trampoline's launchd job, so still killed); polling `launchctl print` for `last exit code` (launchd never reports one while the route monitor is alive in the job, so every connect waited out a 60s timeout and reported a false failure, see 2026-11-04 incident in the log). The job's `sh` wrapper writes wg-quick's exit status to `/var/run/multiguard/<label>.rc` and the script polls that.

## Reconcile UI state with the system

The 2s refresh compares tunnels against `wg show interfaces`. A tunnel marked connected whose interface vanished is reconnected once (single admin prompt, after the default route returns); a tunnel marked disconnected or failed whose interface is up is adopted as connected. The system, not the last command's result, is the source of truth.

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

## Helper trusts its own team instead of a compiled-in Team ID

The client requirement originally contained a literal `TEAM_ID` placeholder that the build script never replaced, so no build could ever connect. The helper now derives the team from its own signature at runtime. Rejected: substituting the Team ID into the Swift source at build time (modifies tracked files, easy to commit by accident) and an `Info.plist` lookup (the helper is a bare binary with an embedded plist, more moving parts for the same result).

## Skip the helper entirely on ad-hoc builds

An ad-hoc helper can never accept a client, yet registering it left a launchd job in `spawn scheduled` that swallowed every XPC call. Ad-hoc builds now never register it and remove stale registrations. Combined with the ping timeout this guarantees the `osascript` fallback is reached.

## No Touch ID for unsigned builds

The `osascript` admin dialog does not support Touch ID. Considered and rejected for now: `AuthorizationCopyRights` + deprecated `AuthorizationExecuteWithPrivileges` (uncertain Touch ID support, deprecated API), `sudo` with `pam_tid` (only works in a terminal), and a NOPASSWD sudoers rule for `wg-quick` (root code execution via `PostUp` in any config). The signed helper removes the prompt altogether, which is the actual goal.

## Fall back to osascript only when the helper is unavailable

Originally any helper error triggered the `osascript` prompt. Once the helper is running, its errors come from `wg-quick` itself; running the same command again as root via `osascript` fails or hangs the same way and only adds a pointless password prompt. Now the fallback applies to `HelperManagerError` (not signed, not installed, unreachable) but not to timeouts or errors the helper returned. Rejected: always falling back (pointless prompts, and `osascript` has no timeout) and never falling back (breaks unsigned builds).

## Timeouts in both helper and app

The app-side timeout alone would free the UI but leave a stuck `wg` child holding the helper; the helper-side kill alone wouldn't cover a helper that stops answering. Both are needed. Rejected: killing the whole process group on timeout — `Process` offers no `setpgid`, and wg-quick's background children (wireguard-go, route monitor) must survive a successful `up` anyway.

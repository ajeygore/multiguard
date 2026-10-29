---
title: Activity Log
tags: [operations, log]
summary: A chronological log tracking all wiki updates and modifications.
---

# Activity Log

This is an append-only log of modifications, updates, and indexing runs performed on the wiki. All logs use the parseable prefix format: `## [YYYY-MM-DD] action | description`.

## [2026-08-10] init | Initialize LLMWiki repository.
- Created `agents.md`, `index.html`, `README.md`.
- Created skeleton documents: `welcome.md`, `getting-started.md`, `index.md`, `log.md`, `overview.md`, `memory.md`, `context.md`.

## [2026-08-10] ingest | Capture MultiGuard project context in wiki.
- Moved `Notes/WireGuardOfficialArchitecture.md` to `raw/WireGuardOfficialArchitecture.md` as immutable source.
- Created project pages: `multiguard-overview.md`, `multiguard-architecture.md`, `multiguard-setup.md`, `multiguard-decisions.md`, `wireguard-official-architecture.md`.
- Updated `wiki/index.md` to catalog the new Project section.
- Prepared to lint, commit, and push.

## [2026-10-02] fix | Connect hang, localized Bash check, working Developer ID helper.
- App: skip helper on ad-hoc builds, XPC ping timeout + error handler, case-insensitive Bash version check.
- Helper: trust clients of its own signing team, case-insensitive Bash check, Homebrew PATH for spawned processes; launchd plist uses `BundleProgram`.
- `build-app.sh`: resolve the Developer ID identity by Team ID.
- Updated `multiguard-architecture.md`, `multiguard-setup.md`, `multiguard-decisions.md`; created `multiguard-troubleshooting.md`.

## [2026-10-05] fix | Disconnect hung forever behind a stuck stats call.
- Helper: requests run concurrently; child processes killed after a timeout; output collected without waiting for EOF; NSError replies keep their message.
- App: every XPC call has an error handler and timeout; osascript fallback only when the helper is unavailable; dead tunnels shown as failed; disconnect of an already-dead tunnel succeeds.
- Updated `multiguard-architecture.md`, `multiguard-decisions.md`, `multiguard-setup.md`, `multiguard-troubleshooting.md`.

## [2026-10-28] fix | Helper busy-looped on EOF and burned 30–40 % CPU.
- `readabilityHandler` now removes itself on empty data; measured 4.2 s → 0.03 s CPU for 20 short commands.
- Updated `multiguard-architecture.md`, `multiguard-troubleshooting.md`.

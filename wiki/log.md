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

## [2026-11-04] incident | MultiGuard tunnels shown as failed/disconnected while up
- Diagnosis: first connect of each tunnel waited ~60s for a launchd exit code that never appears (route monitor alive in the job), then exited 1; the app showed Failed on a healthy tunnel. Re-clicking Connect hit wg-quick's "already exists" and adopted it.
- Fix: exit status passed through a file written by an `sh` wrapper; refresh loop adopts running tunnels shown as failed/disconnected.
- Also landed: per-tunnel launchd jobs (survive authtrampoline idle-exit), XPC error handlers (no hung continuations), single-prompt auto-reconnect after drop/wake, wait for utun removal on disconnect, per-tunnel logs.
- Updated `multiguard-decisions.md`.

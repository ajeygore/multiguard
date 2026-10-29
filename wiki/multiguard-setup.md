---
title: MultiGuard Build & Run
tags: [multiguard, build, setup, codesigning]
summary: How to build, run, and sign MultiGuard.
---

# MultiGuard Build & Run

## Requirements

- macOS 13+
- Xcode 15+ or Swift command-line tools
- Homebrew
- `wireguard-tools` and Bash 4+:

```bash
brew install wireguard-tools bash
```

## Build from terminal

```bash
cd multiguard
swift build
./scripts/build-app.sh
open MultiGuard.app
```

## Open in Xcode

```bash
open Package.swift
```

Then press **Cmd+R**.

## Code signing for no-prompt operation

To enable the privileged helper and avoid repeated password dialogs, sign with an Apple Developer ID:

```bash
DEVELOPER_ID=<TEAM_ID> ./scripts/build-app.sh
open MultiGuard.app
```

To avoid retyping the Team ID, put the call in a personal `build.local.sh`; `*.local.sh` is gitignored so the ID stays out of the repo.

The script picks the keychain identity matching `Developer ID Application: <Name> (<TEAM_ID>)` by its hash and aborts if none exists. Find your identities with:

```bash
security find-identity -p codesigning
```

`-v` may report "0 valid identities" even when signing works; omit it. The Team ID is also listed in Xcode → Settings → Accounts or under *Membership details* at developer.apple.com.

After a rebuild, launchd keeps the previous helper running; restart it with `sudo launchctl kickstart -k system/com.multiguard.helper` (a personal `build.local.sh` can do this after the build). Without a terminal — e.g. Claude Code's `!` prefix, where `sudo` cannot ask for a password — use the dialog instead:

```bash
osascript -e 'do shell script "/bin/launchctl kickstart -k system/com.multiguard.helper" with administrator privileges'
```

On the first **Connect** of a signed build, allow MultiGuard in *System Settings → General → Login Items & Extensions*. That first connect may still use the password prompt; later ones need none.

Unsigned builds ad-hoc sign the app and fall back to the standard macOS administrator prompt on every connect/disconnect. That prompt (`do shell script … with administrator privileges`) never offers Touch ID.

See [Troubleshooting](multiguard-troubleshooting.md) if Connect does nothing.

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
./scripts/build-app.sh            # builds and signs ./MultiGuard.app
./scripts/build-app.sh --install  # also installs to /Applications and launches it
```

`--install` quits a running copy, replaces `/Applications/MultiGuard.app`, verifies the signature and opens it.

The bundle is assembled and signed in a temp directory, then copied out. The repo lives under `~/Documents`, which iCloud syncs, and the file provider attaches `com.apple.FinderInfo` / `com.apple.fileprovider.*` attributes that `xattr -c` cannot strip; `codesign` then fails with "resource fork, Finder information, or similar detritus not allowed". For the same reason the `./MultiGuard.app` copy in the repo may fail `codesign --verify --strict`; the installed copy in `/Applications` is the one to run.

## Open in Xcode

```bash
open Package.swift
```

Then press **Cmd+R**.

## Code signing for no-prompt operation

To enable the privileged helper and avoid repeated password dialogs, sign with an Apple Developer ID:

```bash
DEVELOPER_ID=ABCD123456 ./scripts/build-app.sh
open MultiGuard.app
```

Find your Team ID with:

```bash
security find-identity -v -p codesigning
```

Unsigned builds ad-hoc sign the app and fall back to the standard macOS administrator prompt.

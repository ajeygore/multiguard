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
DEVELOPER_ID=ABCD123456 ./scripts/build-app.sh
open MultiGuard.app
```

Find your Team ID with:

```bash
security find-identity -v -p codesigning
```

Unsigned builds ad-hoc sign the app and fall back to the standard macOS administrator prompt.

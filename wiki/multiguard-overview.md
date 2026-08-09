---
title: MultiGuard Overview
tags: [multiguard, wireguard, vpn, macos]
summary: Purpose and high-level description of the MultiGuard macOS app.
---

# MultiGuard Overview

**MultiGuard** is a native macOS application for managing **multiple WireGuard tunnels simultaneously**.

## Purpose

The official WireGuard macOS client is built around a single active tunnel. MultiGuard fills the gap for users who need several WireGuard endpoints connected at the same time — for example, to reach different private networks or segregate traffic across peers.

## Key capabilities

- Import and persist multiple WireGuard `.conf` files.
- Connect or disconnect tunnels individually or in bulk.
- Detect address and routing conflicts between imported configs.
- Display live connection details: RX/TX bytes, local IP, and routes.
- Run as a menu-bar app for quick toggles.
- Use the official `wg` / `wg-quick` command-line tools as the backend.

## What MultiGuard is not

- It does not reimplement the WireGuard protocol.
- It is not a replacement for the official WireGuard client if you only need one tunnel.
- It is currently macOS-only.

## Repository

- Source: https://github.com/ajeygore/multiguard
- License: MIT

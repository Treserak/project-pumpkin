---
title: Project Pumpkin
emoji: 🎃
colorFrom: orange
colorTo: red
sdk: docker
app_port: 7860
---

# Project Pumpkin

Ultra-lightweight, high-performance Minecraft server powered by **Pumpkin** (written in Rust, compiled statically with `musl`), running inside a minimal Alpine Linux container.

## Architecture
- **Engine**: Pumpkin (Rust, zero Java, sub-50MB RAM footprint).
- **Network**: TCP tunnel via `playit.gg` to bypass NAT/firewalls and provide public Minecraft connectivity.
- **Persistence**: Automated world differential backup daemon with 5-slot FIFO rotation to GitHub Releases.
- **Keep-Alive Dashboard**: Embedded web status server on port 7860.

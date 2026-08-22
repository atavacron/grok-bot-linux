Unofficial wine-less Linux port of Grok Bot **0.24.0**.

Not affiliated with xAI or Cursor. Grok Bot remains proprietary; this release only packages the official Windows payload with Electron 42.1.0 for Linux.

**Artifacts**

- `Grok_Bot_0.24.0_x86_64.AppImage` — double-click / `chmod +x` and run. `--no-sandbox` is built in.
- `Grok_Bot_0.24.0_linux_x64.tar.gz` — portable tree; optional `sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox` for a real Chromium sandbox.
- `grok-bot_0.24.0_amd64.deb` — Debian/Ubuntu package.
- `SHA256SUMS` — checksums for the three files above.

**Requirements**

- CPU: x86_64
- libc: glibc 2.38+ (Ubuntu 24.04+, Fedora 40+, Arch, Debian 13). Ubuntu 22.04 / Debian 12 will not load this build.
- AppImage: FUSE. If `/dev/fuse` is missing, use `--appimage-extract`.

If an older Grok Bot is already running, quit it before launching this one. They share the same Electron app id and the new process will only focus the old window.

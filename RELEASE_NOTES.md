Unofficial wine-less Linux port of Grok Bot **0.30.0**.

Not affiliated with xAI or Cursor. Grok Bot remains proprietary; this release only packages the official Windows payload with Electron 42.1.0 for Linux.

To rebuild it yourself, paste [BUILD-PROMPT.md](https://github.com/atavacron/grok-bot-linux/blob/main/BUILD-PROMPT.md) into a new Grok Build session, or run `./scripts/port.sh 0.30.0` with `originals/Grok_Bot_0.30.0_Setup.exe` present.

**Warning:** the AppImage always runs with `--no-sandbox` (baked into `AppRun`). Chromium renderer processes use your user privileges. Prefer the tarball plus a setuid `chrome-sandbox` if you need the sandbox.

**Artifacts**

- `Grok_Bot_0.30.0_x86_64.AppImage` — make it executable, then run (`--no-sandbox` is **on** and cannot be omitted):

```bash
chmod +x Grok_Bot_*.AppImage
./Grok_Bot_*.AppImage
```

  In the file manager: Properties → Permissions → **Executable as Program**.
- `Grok_Bot_0.30.0_linux_x64.tar.gz` — portable tree; optional `sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox` for a real Chromium sandbox.
- `grok-bot_0.30.0_amd64.deb` — Debian/Ubuntu package.
- `SHA256SUMS` — checksums for the three files above.

**What changed vs 0.29.0**

- Upstream Grok Bot 0.30.0 (still Electron 42.1.0 / ABI 146).
- Native set is unchanged: `cursor-proclist`, `tree-sitter`, `tree-sitter-bash`. `better-sqlite3`, `whichlang-node`, and `@anysphere/tree-chunk-napi` remain absent from the Windows payload.
- Official auto-update is disabled on Linux (`unsupported-platform`). Use a new port when a newer installer appears.

**Requirements**

- CPU: x86_64 (64-bit Intel/AMD). Not ARM.
- libc: glibc 2.38 or newer.
- **Should work on:** Ubuntu 24.04 / 25.04 / 26.04, Linux Mint 22, Pop!_OS 24.04, Fedora 40+, Arch Linux, Debian 13, openSUSE Tumbleweed, and other current glibc desktop distros.
- **Will not work on:** Ubuntu 22.04, Debian 12, RHEL/Rocky/Alma 9, Alpine (musl), ARM.
- AppImage: FUSE. If `/dev/fuse` is missing, use `--appimage-extract`.

If an older Grok Bot is already running, quit it before launching this one. They share the same Electron app id and the new process will only focus the old window.

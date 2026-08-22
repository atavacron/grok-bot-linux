Unofficial wine-less Linux port of Grok Bot **0.24.0**.

Not affiliated with xAI or Cursor. Grok Bot remains proprietary; this release only packages the official Windows payload with Electron 42.1.0 for Linux.

Built with **Grok 4.6 (high)** in Grok Build (**222K / 500K** tokens). To rebuild it yourself, paste [BUILD-PROMPT.md](https://github.com/atavacron/grok-bot-linux/blob/main/BUILD-PROMPT.md) into a new Grok Build session.

AppImage scanned on [VirusTotal](https://www.virustotal.com/gui/file-analysis/MGVkNTRmZmZlZWVkNGMzN2E5YTMyYWYxM2M2ODY0NmQ6MTc4NzM3NDg1Ng==) (SHA-256 `ab722d9385fddc4ea0c28c8402affe3853665ed00fb0bab27bc3dfade2db8e86`).

**Warning:** the AppImage always runs with `--no-sandbox` (baked into `AppRun`). Chromium renderer processes use your user privileges. Prefer the tarball plus a setuid `chrome-sandbox` if you need the sandbox.

**Artifacts**

- `Grok_Bot_0.24.0_x86_64.AppImage` — make it executable, then run (`--no-sandbox` is **on** and cannot be omitted):

```bash
chmod +x Grok_Bot_*.AppImage
./Grok_Bot_*.AppImage
```

  In the file manager: Properties → Permissions → **Executable as Program**.
- `Grok_Bot_0.24.0_linux_x64.tar.gz` — portable tree; optional `sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox` for a real Chromium sandbox.
- `grok-bot_0.24.0_amd64.deb` — Debian/Ubuntu package.
- `SHA256SUMS` — checksums for the three files above.

**Requirements**

- CPU: x86_64 (64-bit Intel/AMD). Not ARM.
- libc: glibc 2.38 or newer.
- **Should work on:** Ubuntu 24.04 / 25.04 / 26.04, Linux Mint 22, Pop!_OS 24.04, Fedora 40+, Arch Linux, Debian 13, openSUSE Tumbleweed, and other current glibc desktop distros.
- **Will not work on:** Ubuntu 22.04, Debian 12, RHEL/Rocky/Alma 9, Alpine (musl), ARM.
- AppImage: FUSE. If `/dev/fuse` is missing, use `--appimage-extract`.

If an older Grok Bot is already running, quit it before launching this one. They share the same Electron app id and the new process will only focus the old window.

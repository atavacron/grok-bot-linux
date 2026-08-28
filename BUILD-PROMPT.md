# Prompt to rebuild this (paste into Grok Build)

The 0.30.0 AppImage is a wine-less Linux port of the official Windows
installer. If you want to rebuild or retarget a newer Grok Bot version
yourself, paste everything below the line into a new Grok Build session
on an x86_64 Linux host. If `originals/Grok_Bot_<ver>_Setup.exe` exists,
prefer that file over downloading.

Do not commit installer binaries, `app.asar`, or AppImages into git. Do
not put local usernames, home directories, hostnames, or env dumps into
docs or commit metadata.

---

**Prompt for Grok Build:**

Create a complete, production-quality, wine-less Linux packaging system
for the official **Grok Bot** desktop app (Electron, shipped by Cursor/xAI
for Windows and macOS only). Implement it from scratch from the official
Windows NSIS installer. Do not clone or copy an existing Linux port.

### Goal

From `Grok_Bot_<version>_Setup.exe`, produce:

- `Grok_Bot_<version>_linux_x64.tar.gz` — portable tree
- `Grok_Bot_<version>_x86_64.AppImage` — when `appimagetool` + squashfs exist
- optional `grok-bot_<version>_amd64.deb`

Primary target: Ubuntu 24.04 x86_64. AppImage is the “any modern glibc
distro” format.

### Upstream facts (verify; do not assume)

- Installer:
  `https://downloads.cursor.com/grokbot/stable/win32-x64/<ver>/Grok_Bot_<ver>_Setup.exe`
- No public `latest.yml` or directory listing. Discover versions by HEAD
  probing semver candidates.
- NSIS extract with `7z` (no Wine). Nested payload is `app-64.7z`, often
  under `$PLUGINSDIR`.
- `resources/app.asar` is platform-neutral JavaScript. **Reuse it
  unchanged.**
- `Grok Bot.exe`, `*.dll`, and `*.node` files in the Windows tree are PE
  (`MZ`). Linux `dlopen` cannot load them. Replace the shell with official
  Electron linux-x64. Replace every **loadable** `.node` with ELF.
- Electron version is embedded in the Windows exe (e.g. `Electron/42.1.0`).
  Make it configurable; default to whatever the exe reports.
- Native addons live under `resources/app.asar.unpacked/dist/deps/`, not
  `node_modules`. Running `@electron/rebuild` at the app root finds
  nothing. Drive each module from its `dist/deps/<name>` directory.
- Observed addons (0.30.0; re-inventory after extract via
  `runtime-deps-manifest.json`):
  - `cursor-proclist` — private; Windows tree ships the JS wrapper
    (`cursor_proclist_scan_async` / `cursor_proclist_system_memory`) but
    strips the `.cc` files. Linux `/proc` implementation. Tuple is
    `[pid, ppid, name, extensionId, cpuTimeMs, memoryMB, argv, ownerAgentId, requestId]`.
    `cpuTimeMs` and `memoryMB` must be JS numbers (the host sampler does
    arithmetic). `system_memory` may return null on Linux. Rebuild with
    `node-gyp --runtime electron --target <electron> --dist-url https://electronjs.org/headers`.
  - `tree-sitter` / `tree-sitter-bash` — `npm pack` the pinned versions
    and copy `prebuilds/linux-x64/*.node`. **Also** copy the ELF to
    `build/Release/` using the names the asar overlay already lists
    (`tree_sitter_runtime_binding.node`, `tree_sitter_bash_binding.node`).
    Deleting `build/Release` without replacing it makes Electron look on
    disk for an unpacked path that no longer exists and crash.
  - `web-tree-sitter` — WASM + JS; copy unchanged.
  - Older payloads (0.24.x) also had `better-sqlite3`, `whichlang-node`,
    and `@anysphere/tree-chunk-napi`. Drive each module **only if its
    directory exists** under `dist/deps`. Do not invent missing addons.
  - If `better-sqlite3` is present: fetch a GitHub prebuild matching
    Electron’s ABI (Electron 42 → ABI 146) and install at
    `build/Release/better_sqlite3.node`.
  - If `whichlang-node` is present: `npm pack whichlang-node-linux-x64-gnu@<pinned>`
    and place `whichlang-node.linux-x64-gnu.node` next to `index.js`.
  - If `@anysphere/tree-chunk-napi` is present: ship a tiny N-API stub
    named `tree-chunk-napi.linux-x64-gnu.node` exporting empty classes
    `Chunk`, `ChunkerRouter`, `CompressedFileOutline`, `FileTree`,
    `PartialFileContext`.
- Dead PE leftovers that Linux loaders never resolve may remain
  (`prebuilds/win32-*`, `*.win32-*.node`). Fail the build if any other
  `.node` still has an MZ header.
- **Asar overlay:** files you add under `app.asar.unpacked` that were
  **not** in the original asar unpacked index are invisible when the app
  `require()`s through `app.asar`. After fixing natives, extract the
  **original** Windows `app.asar` **next to its matching**
  `app.asar.unpacked` (extracting a mutated tree fails), overlay ELF
  `.node` files, drop remaining PE `.node` files, then
  `asar pack --unpack "*.node"`. Natives cannot be `dlopen`ed from inside
  asar.
- Compiling C++ on Ubuntu 24.04 often requires **glibc 2.38+** at
  runtime. Document that. Ubuntu 22.04 / Debian 12 will not load such
  binaries. To support 22.04, compile `cursor-proclist` against an older
  glibc (container), do not just claim 22.04 support.
- AppImage: squashfs cannot carry root-owned setuid `chrome-sandbox`
  when built as a normal user. Bake `--no-sandbox` into `AppRun` so
  anyone who downloads the AppImage can run it without extra flags.
  **Warn in the README** that `--no-sandbox` is always on. The tarball
  should still document `chown root:root chrome-sandbox && chmod 4755`
  for people who want the real sandbox.
- All Grok Bot builds share Electron app id `sand` and
  `~/.config/Grok Bot`. A second launch focuses the first window.
  Document: quit any existing Grok Bot before testing a new build.
- Detect Electron from the Windows exe with `strings` (`Electron/x.y.z`).
- If system `7z` is missing, download official 7-Zip `7zz` linux-x64
  into a gitignored `.cache/tools` rather than requiring sudo.
- Prefer distro Python 3.12 for node-gyp if conda Python 3.13+ is first
  on `PATH`.
- Never write local usernames, home paths, hostnames, or env dumps into
  README, release notes, LICENSE, or git author fields. Use a GitHub
  noreply author. Do not mention other people’s ports by name.

### Scripts to produce

- `scripts/detect-version.sh` — HEAD-probe win32 installer URLs, emit
  `version=` / `is_new=` (and `$GITHUB_OUTPUT` when set).
- `scripts/port.sh <version>` — download, extract, fuse Electron, rebuild
  natives, repack asar, tarball, optional AppImage and `.deb`.
- Native sources for `cursor-proclist` and the tree-chunk stub under
  `scripts/native/`.
- `.github/workflows/linux-port.yml` — scheduled HEAD probe, build,
  GitHub Release. Do not upload proprietary bits into git; only Release
  assets.
- `VERSION`, `.gitignore` (`dist/`, `.cache/`, `*.AppImage`, `*.exe`, …),
  README, license covering **scripts only**.

### Packaging details

- Stage layout: Electron linux zip files + `grok-bot` binary +
  `resources/app.asar` + `resources/app.asar.unpacked`.
- AppDir `AppRun`:
  `exec "$HERE/usr/bin/grok-bot" --no-sandbox "$@"`
- Desktop `Exec=grok-bot --no-sandbox`. Extract an icon from asar
  (`app-icon*.png`) into the AppDir; `asar extract-file` writes into cwd.
- Fail the AppImage step softly if `appimagetool`/`mksquashfs` is missing.
- Optional `.deb` installs to `/opt/grok-bot` with a `postinst` that
  tries to setuid `chrome-sandbox`.

### Docs the agent must write

README must include: unofficial/not affiliated; how the port works
(asar reused, PE replaced); AppImage `--no-sandbox` **warning**; tarball
sandbox instructions; distros that should work (glibc 2.38+: Ubuntu
24.04+, Fedora 40+, Arch, Debian 13, …) vs will not (Ubuntu 22.04,
Debian 12, RHEL 9, Alpine, ARM); how to build locally; this paste-ready
prompt; license note that Grok Bot is proprietary.

### Verification before claiming done

- `file grok-bot` is ELF x86-64.
- Every loadable `.node` is ELF, not MZ.
- `ELECTRON_RUN_AS_NODE=1` can `require()` every **required** native from
  the payload’s `runtime-deps-manifest.json` (0.30.0: tree-sitter,
  tree-sitter-bash, cursor-proclist `cursor_proclist_scan_async`). Set
  `NODE_PATH` to `resources/app.asar/dist/deps` the same way the host
  process does.
- Launch with a **fresh** `--user-data-dir` so an already-running Grok
  Bot does not steal the instance. Main process must get past native
  loads (no `invalid ELF header`, no missing `build/Release/*.node`).
- AppImage contains `--no-sandbox` in `AppRun`.
- Git author is a noreply identity. Grep the tree for home directories
  and local usernames before you push.

Start with version detection and `port.sh`, then CI and docs. Inventory
natives from the extracted tree (and `runtime-deps-manifest.json` when
present) rather than hard-coding guesses. Prefer
`originals/Grok_Bot_<ver>_Setup.exe` when that file exists.

---

End of prompt.

# AppImage string audit (v0.30.0)

File: `Grok_Bot_0.30.0_x86_64.AppImage`  
SHA-256: `a502dcb366ca7619c553309e355e452d49badea27657dc9a83266353932ca328`

The AppImage squashfs / staged tree was searched for builder identity: home directories, local usernames, hostnames, emails, and compile paths inside ELF `.node` files.

**Result: no builder PII.** `AppRun`, the `.desktop` file, and all shipped natives are generic. Hits for the words “spock” and “aurora” are upstream product strings, not a machine account.

## What was checked

| Location | Finding |
| --- | --- |
| `AppRun` | `exec …/grok-bot --no-sandbox` only |
| `grok-bot.desktop` | Name/version 0.30.0, no user paths |
| `*.node` (tree-sitter, tree-sitter-bash, cursor-proclist) | No `/home/…` or `/tmp/grokbot-…` compile paths |
| Outer AppImage ELF | No local identity strings |
| `resources/app.asar` | Official Grok Bot payload; see below |

## Word collisions (not identity)

These are the only notable substring matches. Context is quoted so they are not mistaken for a username or hostname.

**`spock` (in `app.asar`)** — emoji short name for U+1F596 (Vulcan salute):

```text
"1F596":"spock-hand"
```

**`aurora` in `app.asar`** — AWS Aurora as a database-provider enum in Grok Bot, plus a font-family name in the same upstream payload.

**`aurora` in `grok-bot` (Electron/Chromium)** — USB product names in Chromium’s device list (`Enermax Aurora Micro Wireless Receiver`, `Gaming Desktop [Aurora R4]`, `Pixelmatix Aurora`).

`/home/` hits inside `app.asar` are upstream sandbox paths (`/home/box`, `/home/web_user`, a constructed `/home/"+t`), not a builder home directory.

A real leak would look like `/home/<user>/…`, `<user>@<host>`, or a machine hostname baked into a binary. None of those patterns are in the Linux natives or packaging files.

## Other release archives

The AppImage squashfs is stored as uid/gid `0` (root), with no Unix login name.

The `.tar.gz` and `.deb` on the release are packed with **numeric owner `0/0`** (or `root/root`). They do not store a local login name in the archive headers.

## Runtime (not in the file)

When the app runs, Electron stores session data under the **current user’s** `~/.config/Grok Bot`. That directory is created on the machine that launches it. It is not packed into the AppImage.

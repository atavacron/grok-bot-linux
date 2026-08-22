# AppImage string audit (v0.24.0)

File: `Grok_Bot_0.24.0_x86_64.AppImage`  
SHA-256: `ab722d9385fddc4ea0c28c8402affe3853665ed00fb0bab27bc3dfade2db8e86`  
[VirusTotal](https://www.virustotal.com/gui/file-analysis/MGVkNTRmZmZlZWVkNGMzN2E5YTMyYWYxM2M2ODY0NmQ6MTc4NzM3NDg1Ng==)

The AppImage was extracted (`--appimage-extract`) and searched for builder identity: home directories, local usernames, hostnames, emails, and compile paths inside ELF `.node` files.

**Result: no builder PII.** `AppRun`, the `.desktop` file, and all shipped natives are generic. Hits for the words “spock” and “aurora” are upstream product strings, not a machine account.

## What was checked

| Location | Finding |
| --- | --- |
| `AppRun` | `exec …/grok-bot --no-sandbox` only |
| `grok-bot.desktop` | Name/version 0.24.0, no user paths |
| `*.node` (sqlite, tree-sitter, whichlang, cursor-proclist, tree-chunk stub) | No `/home/…` or `/tmp/grokbot-…` compile paths |
| Outer AppImage ELF | No local identity strings |
| `resources/app.asar` | Official Grok Bot payload; see below |

## Word collisions (not identity)

These are the only notable substring matches. Context is quoted so they are not mistaken for a username or hostname.

**`spock` (1 place, `app.asar`)** — emoji short name for U+1F596 (Vulcan salute):

```text
"1F596":"spock-hand"
```

**`aurora` in `app.asar`** — AWS Aurora as a database-provider enum in Grok Bot:

```text
DATABASE_PROVIDER_AURORA
DATABASE_PROVIDER_PLANETSCALE
```

**`aurora` in `grok-bot` (Electron/Chromium)** — USB product names in Chromium’s device list, including:

```text
Enermax Aurora Micro Wireless Receiver
Gaming Desktop [Aurora R4]
Pixelmatix Aurora
Pixelmatix Aurora (bootloader)
```

A real leak would look like `/home/<user>/…`, `<user>@<host>`, or a machine hostname baked into a binary. None of those patterns are in this AppImage.

## Runtime (not in the file)

When the app runs, Electron stores session data under the **current user’s** `~/.config/Grok Bot`. That directory is created on the machine that launches it. It is not packed into the AppImage.

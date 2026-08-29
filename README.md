# mac-screenshots-to-photos

**iPhone screenshots go to Photos. Why don't Mac screenshots?**

On iPhone, every screenshot lands in your photo library — searchable, synced,
backed up. On the Mac, the same keystroke dumps a PNG onto your Desktop and
walks away. This tiny project closes that gap using **only built-in macOS
parts** — no third-party apps, no background daemons, nothing to keep updated.

[中文说明 / Chinese README](README.zh-CN.md)

## What you get

```
Cmd+Shift+3/4          (you take a screenshot)
   │
   ▼
watched folder         (macOS saves it there — a built-in setting)
   │
   ▼
Folder Action          (macOS notices the new file — a built-in watcher)
   │
   ▼
14-line AppleScript    (tells Photos to import it; deletes the file
   │                    ONLY if the import succeeded)
   ▼
Photos  ──►  iCloud  ──►  your iPhone, iPad, other Macs
```

- Screenshots appear in Photos within seconds, then sync everywhere.
- Photos OCRs them — you can **search your screenshots by the text in them**.
- The source file deletes itself. No screenshot graveyard on your Desktop.
- Fail-safe by construction: if the import ever fails, the file simply stays
  in the folder. Nothing is deleted that wasn't safely imported first.

## Install

```bash
git clone https://github.com/gnehiur/mac-screenshots-to-photos.git
cd mac-screenshots-to-photos
./install.sh
```

**Before running it**, open **Photos → Settings… → General** and check
**"Importing: Copy items to the Photos library"**. The installer asks you to
confirm this and refuses to proceed otherwise — see *The dead-link trap* below
for why this matters.

macOS will ask for a couple of permissions on first run (control System
Events; later, control Photos when the first screenshot imports). Each is
asked once — click Allow.

Custom watched folder: `./install.sh "$HOME/somewhere/else"`.

To undo everything: `./uninstall.sh` (screenshots go back to the Desktop;
nothing in your library is touched).

## The dead-link trap (read this once)

Photos can import two ways:

- **Copy** (checkbox ON): Photos stores its own copy. The original file
  becomes disposable, and the photo uploads to iCloud.
- **Reference** (checkbox OFF): Photos stores only a *note* — "the file
  lives over there". Referenced items **never upload to iCloud**, and if the
  original file is ever moved or deleted, the photo becomes a dead link
  showing only its thumbnail.

This pipeline deletes source files after import. Combine that with
reference-mode and every screenshot would be orphaned the instant it was
imported. That's why copy-mode is a hard precondition, checked at install
time. (This README exists because its author learned this the hard way, via
1,242 dead links.)

## Design notes

Everything is a stock macOS mechanism wired together:

| Stage | Mechanism | Where |
|---|---|---|
| Save location | `defaults write com.apple.screencapture location` | system preference |
| File watching | Folder Actions | System Events, built-in |
| Import | Photos' AppleScript interface | `import ... skip check duplicates` |
| Sync / OCR / search | iCloud Photos + Live Text | free with Photos |

Why not Automator's stock "Import Files into Photos" action? It's a black
box: when it breaks (and one day it silently did), it says "script failed"
and nothing else. Fourteen lines of visible AppleScript do the same job,
fail loudly, and can be fixed by reading them.

The delete is *sequenced after* the import inside the same `try` block —
the `rm` line is unreachable unless the import line completed without
throwing. That single ordering decision is the whole safety story.

## FAQ

**Does this eat my iCloud storage?** Yes, like iPhone screenshots do —
figure a few GB per year for a heavy screenshotter. They're first-class
library items, so pruning them later is normal photo deletion.

**Can I keep screenshots out of my main timeline?** Photos already groups
them under Media Types → Screenshots, and smart albums can filter them.

**What about screenshots I take while Photos is busy or the disk is full?**
The import fails, so the delete never runs — the file waits in the watched
folder. Re-trigger by moving it out and back in, or just open the folder
and import manually.

**Older macOS?** Tested on macOS 26. Anything recent enough to have
Folder Actions and Photos' AppleScript dictionary should work.

## License

MIT

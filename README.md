# mac-screenshots-to-photos

**iPhone screenshots go to Photos. Why don't Mac screenshots?**

On iPhone, every screenshot lands in your photo library — searchable, synced,
backed up. On the Mac, the same keystroke dumps a PNG onto your Desktop and
walks away. This tiny project closes that gap, in one of two modes:

- **Classic** — **only built-in macOS parts**: no third-party apps, no
  background daemons, nothing to keep updated. Screenshots reach Photos
  within seconds.
- **Fast** — one tiny resident helper (~200 lines of Swift, zero
  dependencies) that also puts every screenshot **on the clipboard about
  0.1 s after you take it**, so you can Cmd+V it straight into a chat.
  See [Fast mode](#fast-mode-screenshot--clipboard-in-01-s).

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

## Install (classic mode)

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

## Fast mode: screenshot → clipboard in ~0.1 s

Most screenshots are taken to be pasted somewhere. Classic mode leaves you
dragging the file around; fast mode makes the screenshot *already be on the
clipboard* by the time you switch to the chat window — and still files it in
Photos.

```
Cmd+Shift+3/4 (or the Screenshot app)
   │
   ▼
watched folder          (file lands at once — floating thumbnail turned off)
   │  FSEvents, ~ms
   ▼
screenshot-sync         (resident LaunchAgent, fast/main.swift)
   ├─► clipboard        (PNG bytes, ~0.1 s after the shot)  ──►  Cmd+V
   └─► Photos           (PhotoKit, copies into the library; then deletes
                         the source file ONLY if the import succeeded)
```

```bash
cd mac-screenshots-to-photos/fast
./install.sh                     # or ./install.sh "$HOME/somewhere/else"
```

Needs `swiftc` (Xcode Command Line Tools: `xcode-select --install`). The
installer builds the helper, installs it to `~/Applications/screenshot-sync.app`,
runs it as LaunchAgent `com.gnehiur.screenshot-sync`, turns off the floating
thumbnail, and disables a classic Folder Action on the same folder so nothing
is imported twice. macOS asks once to let it **add to Photos** — click Allow.
Log: `~/Library/Logs/screenshot-sync.log`. Undo: `fast/uninstall.sh`.

**Two Macs side by side (Universal Control)?** The shutter sound is the same
file on every Mac (`/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif`),
on the read-only system volume, so you can't tell which Mac just took the
shot. Give one of them an extra cue, played right after the shutter:

```bash
./install.sh "$HOME/Pictures/Screenshots Auto-Import" /System/Library/Sounds/Bottle.aiff
```

Two sounds = that Mac, one sound = the other. The cue fires on the temp file
macOS creates ~10 ms after the shutter, then waits 140 ms (third argument, in
ms) so it isn't swallowed by the shutter's attack and the speaker waking up. `tools/sound-picker/` is a small
local page for auditioning candidates (`python3 build.py`, then serve the
folder and open `index.html`). Only screenshots saved to the folder trigger the
cue; Ctrl+Shift+Cmd+3/4 (clipboard-only) writes no file and stays silent.

**Why classic mode is slow.** Folder Actions are not instant: macOS batches
folder changes and fires the action 1–5 s later, then has to spin up the
script (an Automator workflow adds another second or two). On top of that,
the floating thumbnail in the corner holds the file back ~5 s before it is
written at all. Fast mode removes all three: FSEvents with zero latency, an
already-running process, thumbnail off.

**Why it puts image bytes, not a file, on the clipboard.** A copied *file* is
just a path. It breaks the moment the source is deleted (which this pipeline
does), and it means nothing on another Mac. The helper writes the PNG data
itself (`public.png`), so the paste works after the file is gone, in any app
that accepts images — and remote-desktop tools that sync clipboards (e.g. UU
Remote) carry the actual image across to the other machine.

**How it knows the file is complete.** macOS writes a hidden
`.Screenshot…png` temp file and renames it when done. The helper ignores dot
files and also checks that the PNG ends with its `IEND` chunk before using it,
retrying every 50 ms for up to 5 s.

**No dead-link trap here.** PhotoKit always copies the file into the
library, regardless of the "Copy items" checkbox. The delete still only runs
after a successful import; if Photos access is denied, screenshots still go
to the clipboard and simply stay in the folder.

**Two Macs?** Install it on each. With iCloud Photos on, both libraries fill
up from either machine; nothing in this project syncs across Macs itself.

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

Classic mode — everything is a stock macOS mechanism wired together:

| Stage | Mechanism | Where |
|---|---|---|
| Save location | `defaults write com.apple.screencapture location` | system preference |
| File watching | Folder Actions | System Events, built-in |
| Import | Photos' AppleScript interface | `import ... skip check duplicates` |
| Sync / OCR / search | iCloud Photos + Live Text | free with Photos |

Fast mode swaps the middle of that chain:

| Stage | Classic | Fast |
|---|---|---|
| File watching | Folder Actions (1–5 s) | FSEvents, latency 0 (ms) |
| Clipboard | — | `NSPasteboard`, PNG bytes |
| Import | Photos AppleScript | PhotoKit `PHAssetCreationRequest` (always copies) |
| Permission | control System Events + Photos | add to Photos only |
| Runs | on demand | LaunchAgent, 10–35 MB RAM, idle otherwise |

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

**Does fast mode touch screenshots that were already in the folder?** No.
It only handles files created after it started.

**What about screenshots I take while Photos is busy or the disk is full?**
The import fails, so the delete never runs — the file waits in the watched
folder. Re-trigger by moving it out and back in, or just open the folder
and import manually.

**Older macOS?** Tested on macOS 26. Anything recent enough to have
Folder Actions and Photos' AppleScript dictionary should work.

## License

MIT

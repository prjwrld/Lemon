<p align="center"><img src="Lemon/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" alt="Lemon icon"></p>

<h1 align="center">Lemon</h1>

<p align="center">Convert and edit files by dragging them. A menu bar app for macOS, built with Liquid Glass.</p>

> **Open source, paid builds.** Lemon's code is free under the [GPL-3.0](LICENSE). The signed, notarized app
> with automatic updates is a one-time purchase from [fixbyai.in/lemon](https://fixbyai.in/lemon), which keeps
> the project going.

---

Start dragging files in Finder (or any app), then hold **Shift**. A glass wheel appears under the pointer.
Drop the files on a format and Lemon saves converted copies next to the originals.
Hold **Option + Shift** instead for the tools wheel: crop, compress, trim, redact and more.
Keep holding the keys until you drop; let go of them and the wheel closes.

Lemon never changes or replaces your files. Every result is a new copy; if a name is taken it adds a
number (`photo 2.png`). Everything happens on your Mac. Lemon goes online only to activate or check a licence key.

## What it does

| Files | Convert to (Shift) | Tools (Option + Shift) |
|---|---|---|
| Pictures (JPG, PNG, HEIC, WebP, AVIF, TIFF, BMP, SVG) | PNG, JPG, WebP, HEIC, TIFF, AVIF, BMP, PDF, Word | Compress, Metadata, Edit Photo, Annotate, Background, Crop, Redact, Read QR; several at once: Create PDF, Collage |
| Video (MP4, MOV, MKV, WebM, AVI, WMV…) and GIF | MP4, MOV, MKV, WebM, AVI, WMV, GIF, MP3 | Trim, Crop, Speed, Snapshots, Split, Redact, Compress, Metadata, Mute; several: Join |
| Audio (MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA) | MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA | Trim, Normalize, Visualizer, Channels (mono ↔ stereo), Bleep, Compress, Metadata; several: Join |
| PDF | Word, JPG, PNG, Text | Pages, Split, Compress, Metadata; several: Merge |
| Text and subtitles (TXT, SRT, VTT) | PDF, JPG, PNG, SRT, VTT, Text | |
| Archives (ZIP, TAR, GZIP, RAR, 7Z) | ZIP, TAR, GZIP | Extract |

The keys are configurable in Settings.

## Requirements

- macOS 26 (Tahoe) or later
- A Mac with Apple Silicon

## Selling Lemon

Lemon is a one-time purchase, **₹799**, sold through a **Razorpay Payment Page** (UPI and cards, including cards
from outside India): https://rzp.io/rzp/uuLxRW7 (test mode: https://rzp.io/rzp/mkqmlar). Website:
https://fixbyai.in/lemon (in the FixbyAI-Site project).

- **Free uses:** every feature works for 15 conversions or tools (`StoreConfig.freeUses`). Practice files in the
  welcome tour don't count. After that, the wheel opens the Buy window instead. The count is kept in the Keychain,
  in preferences and in a hidden file, and the lowest wins (`FreeUses` in `License.swift`), so deleting one copy
  doesn't reset it.
- **Licence keys:** Razorpay doesn't make keys, so Lemon's own key server (`Server/`, a Cloudflare Worker at
  lemon-licences.edupurspose.workers.dev) does: one unique `LEMON-…` key per Lemon Page payment, shown on the
  "Find your key" page (fixbyai.in/lemon/key), 2 Macs per key, turned off by a refund. Setup and admin:
  [Server/README.md](Server/README.md).
- **Regular checks:** Lemon confirms the key at launch and about once a day. If the server says the key is no longer
  valid (refunded, disabled, made up), the licence is removed. Offline, Lemon keeps working for 30 days since the
  last successful check, then asks to connect and click Check Now.
- **Lemon Squeezy** (with global tax handling) is built in but switched off (`StoreConfig.lemonSqueezyEnabled`). To
  use it: turn on licence keys for the product (activation limit 2), fill in its checkout link and product ID, and
  switch it on; Macs outside India then see it first.
- All store links live in `StoreConfig` (`Lemon/Core/License.swift`); `scripts/release.sh` refuses to build while
  any are placeholders.

Testing in a Debug build (no dragging needed): `-LemonTestSetUses N`, `-LemonTestConvert /path/file -LemonTestFormat png`,
`-LemonTestActivate KEY`, `-LemonTestLastChecked DAYS`, `-LemonTestOffline YES` and
`-LemonTestKeyServer http://localhost:8787` (see `Server/test.sh`), e.g.
`build/Build/Products/Debug/Lemon.app/Contents/MacOS/Lemon -LemonTestSetUses 0 -LemonTestConvert ~/photo.jpg`.

## Build from source

You need Xcode 26 or later and [Homebrew](https://brew.sh).

```sh
cd Lemon
./scripts/build-ffmpeg.sh        # once: builds the LGPL FFmpeg helper into Vendor/bin (takes a while)
open Lemon.xcodeproj             # then press ⌘R
```

Without the FFmpeg helper Lemon still builds and runs, but audio, video, GIF and WebP features are off.

Command-line build:

```sh
xcodebuild -project Lemon.xcodeproj -scheme Lemon -derivedDataPath build build
open build/Build/Products/Debug/Lemon.app
```

Debug builds are signed ad hoc, so you don't need an Apple developer account to run them.

### Tests

`./scripts/test-engines.sh` makes sample files and runs every conversion route and tool against them.
The results are left in `build/engine-tests/` so you can open them.

### Design helpers (Debug builds)

- `open build/Build/Products/Debug/Lemon.app --args -LemonDemoWheel YES` shows the wheel for 8 seconds, then opens and closes it once more.
  Add `-LemonDemoMode tools` for the tools wheel, `-LemonDemoFile /path/file` to pick the file type,
  and `-LemonDemoBackdrop /path/image` to put a picture behind it.
- `--args -LemonDemoEditor crop -LemonDemoFile /path/photo.jpg` opens an editor directly.
- `--args -LemonDemoSettings shortcuts` opens Settings on a page (`general`, `shortcuts`, `formats`, `saving`,
  `supported`, `licence`, `about`).

## How it's organised

| Folder | What's in it |
|---|---|
| `Lemon/Wheel` | Spotting file drags (`DragWatcher`), the floating panel and drop target, the glass wheel |
| `Lemon/Core` | File kinds, formats, tools, the action catalog (which choices fit which files), settings, jobs, safe saving |
| `Lemon/Engines` | Conversions: ImageIO, PDFKit and Core Text, FFmpeg, subtitles, bsdtar for archives, Word writer |
| `Lemon/Tools` | The tools, and `Processor`, which runs a wheel choice and saves the results |
| `Lemon/Editors` | The editing windows (crop, photo, annotate, timeline…) |
| `Lemon/Screens` | Progress panel, Settings, welcome tour, Buy window, shared glass window |
| `scripts` | FFmpeg build, engine tests, app and menu bar icons, release |

Spotting drags needs no special permission: Lemon watches mouse clicks and the system drag pasteboard.

## Releasing (maintainer)

```sh
./scripts/release.sh 1.0.2 notes.txt   # notes: one change per line, shown in the update window
```

It archives Lemon with a timestamp build number, signs it with Developer ID (Sparkle's helpers inside out), packs
the DMG with its install window (`Config/dmg-settings.py`), has Apple notarize and staple it, signs the update with
Lemon's update key (Keychain, account `lemon`), rewrites `Updates/public/appcast.xml` and deploys the
`lemon-updates` site. Installed copies pick it up within a day (a small delta when possible), download it in the
background and install it when Lemon quits; https://fixbyai.in/lemon/download always gives the newest DMG.

It reuses tools set up for Rightly: the `rightly-notary` notarytool profile (override with `NOTARY_PROFILE`),
Sparkle's `bin` tools and `dmgbuild` (paths at the top of the script). Keep `Updates/public/*.dmg`: they're not in
git, and Sparkle uses them for delta updates. Debug builds never update themselves.

## Licence

Copyright © 2026 Prajwal Prasad. Lemon is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License, version 3 or (at your option) any later version. It comes with no
warranty. See [LICENSE](LICENSE). The Lemon name and icon are not covered by the GPL: forks should use their own.

Audio and video features use [FFmpeg](https://ffmpeg.org) 9.0.2, built by `scripts/build-ffmpeg.sh` without
GPL or non-free parts and shipped as a separate, replaceable helper under the
[LGPL 2.1](Lemon/Licenses/FFmpeg-LGPL-2.1.txt). That build includes LAME and mpg123 (LGPL 2.1) and libvorbis,
libogg, Opus, libvpx and libwebp (BSD licences). To stay within the LGPL: keep shipping its licence text
(Settings → About), keep FFmpeg a separate program, link its exact source, and send the build settings
(`scripts/build-ffmpeg.sh`) to anyone who asks.

Lemon is an independent project and is not affiliated with Apple or any other app.

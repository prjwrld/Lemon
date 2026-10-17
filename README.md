<p align="center"><img src="Lemon/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" alt="Lemon icon"></p>

<h1 align="center">Lemon</h1>

<p align="center">Convert and edit files by dragging them. A menu bar app for macOS, built with Liquid Glass.</p>

> **Private repository.** Lemon is closed-source, paid software (one-time purchase). Don't share this code.

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

Lemon is a one-time purchase sold through [Lemon Squeezy](https://www.lemonsqueezy.com), with licence keys.

- **Free uses:** every feature works for 15 conversions or tools (`StoreConfig.freeUses`). Practice files in the
  welcome tour don't count. After that, the wheel opens the Buy window instead.
- **Licence keys:** activated, checked and deactivated with the Lemon Squeezy licence API
  (`Lemon/Core/License.swift`). The key and remaining uses are kept in the Keychain, so they survive a reinstall.
  Debug builds keep them in UserDefaults (`debug.keychain.*`) to avoid Keychain password prompts.
- **Before release, fill in `StoreConfig`** in `Lemon/Core/License.swift`: checkout link, product ID (so only keys
  for Lemon are accepted), price text, website, privacy and terms pages, and support email. All are placeholders now.
- In Lemon Squeezy, turn on **licence keys** for the product, with an activation limit (for example 2 Macs).

To test the trial in a Debug build: `defaults write com.prajwal.Lemon debug.keychain.usesLeft 1`.
To reset it: `defaults delete com.prajwal.Lemon debug.keychain.usesLeft`.

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

One time: `xcrun notarytool store-credentials lemon-notary --apple-id YOUR_APPLE_ID --team-id WR42UXPTXW`

Then `./scripts/release.sh` builds, signs with Developer ID, notarizes and staples `build/Lemon.zip`,
ready to upload to Lemon Squeezy and your website.

## Licence

Copyright © 2026 Prajwal Prasad. All rights reserved. See [LICENSE](LICENSE).

Audio and video features use [FFmpeg](https://ffmpeg.org) 9.0.2, built by `scripts/build-ffmpeg.sh` without
GPL or non-free parts and shipped as a separate, replaceable helper under the
[LGPL 2.1](Lemon/Licenses/FFmpeg-LGPL-2.1.txt). That build includes LAME and mpg123 (LGPL 2.1) and libvorbis,
libogg, Opus, libvpx and libwebp (BSD licences). To stay within the LGPL: keep shipping its licence text
(Settings → About), keep FFmpeg a separate program, link its exact source, and send the build settings
(`scripts/build-ffmpeg.sh`) to anyone who asks.

Lemon is an independent project and is not affiliated with Apple or any other app.

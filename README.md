<p align="center"><img src="Lemon/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" alt="Lemon icon"></p>

<h1 align="center">Lemon</h1>

<p align="center">Convert and edit files by dragging them. A free, open-source menu bar app for macOS, built with Liquid Glass.</p>

---

Start dragging files in Finder (or any app), then hold **Shift**. A glass wheel appears under the pointer.
Drop the files on a format and Lemon saves converted copies next to the originals.
Hold **Option + Shift** instead for the tools wheel: crop, compress, trim, redact and more.
Keep holding the keys until you drop; let go of them and the wheel closes.

Lemon never changes or replaces your files. Every result is a new copy; if a name is taken it adds a
number (`photo 2.png`). Everything happens on your Mac: Lemon never goes online and collects nothing.

## What it does

| Files | Convert to (Shift) | Tools (Option + Shift) |
|---|---|---|
| Pictures (JPG, PNG, HEIC, WebP, AVIF, TIFF, BMP, SVG) | PNG, JPG, WebP, HEIC, TIFF, AVIF, BMP, PDF, Word | Compress, Metadata, Edit Photo, Annotate, Background, Crop, Redact, Read QR; several at once: Create PDF, Collage |
| Video (MP4, MOV, MKV, WebM, AVI, WMV…) and GIF | MP4, MOV, MKV, WebM, AVI, WMV, GIF, MP3 | Trim, Crop, Speed, Snapshots, Split, Mute, Redact, Compress, Metadata; several: Join |
| Audio (MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA) | MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA | Trim, Normalize, Mono/Stereo, Visualizer, Bleep, Compress, Metadata; several: Join |
| PDF | Word, JPG, PNG, Text | Pages, Split, Compress, Metadata; several: Merge |
| Text and subtitles (TXT, SRT, VTT) | PDF, JPG, PNG, SRT, VTT, Text | |
| Archives (ZIP, TAR, GZIP, RAR, 7Z) | ZIP, TAR, GZIP | Extract |

The keys are configurable in Settings.

## Requirements

- macOS 26 (Tahoe) or later
- A Mac with Apple Silicon

## Install

Download the latest `Lemon.zip` from [Releases](https://github.com/prjwrld/Lemon/releases), unzip it and move
Lemon to Applications. Releases are signed and notarized by Apple.

## Build from source

You need Xcode 26 or later and [Homebrew](https://brew.sh).

```sh
git clone https://github.com/prjwrld/Lemon.git
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

## How it's organised

| Folder | What's in it |
|---|---|
| `Lemon/Wheel` | Spotting file drags (`DragWatcher`), the floating panel and drop target, the glass wheel |
| `Lemon/Core` | File kinds, formats, tools, the action catalog (which choices fit which files), settings, jobs, safe saving |
| `Lemon/Engines` | Conversions: ImageIO, PDFKit and Core Text, FFmpeg, subtitles, bsdtar for archives, Word writer |
| `Lemon/Tools` | The tools, and `Processor`, which runs a wheel choice and saves the results |
| `Lemon/Editors` | The editing windows (crop, photo, annotate, timeline…) |
| `Lemon/Screens` | Progress panel, Settings, welcome tour, shared glass window |
| `scripts` | FFmpeg build, engine tests, app icon, release |

Spotting drags needs no special permission: Lemon watches mouse clicks and the system drag pasteboard.

## Releasing (maintainer)

One time: `xcrun notarytool store-credentials lemon-notary --apple-id YOUR_APPLE_ID --team-id WR42UXPTXW`

Then `./scripts/release.sh` builds, signs with Developer ID, notarizes and staples `build/Lemon.zip`,
ready to attach to a GitHub release.

## Contributing

Bug reports and ideas are welcome in [Issues](https://github.com/prjwrld/Lemon/issues). Pull requests too:
please run `./scripts/test-engines.sh` first.

## Licence

Lemon is free software under the [GNU General Public License v3.0](LICENSE) or later.

Its audio and video features use [FFmpeg](https://ffmpeg.org) 9.0.2, built by `scripts/build-ffmpeg.sh` without
GPL or non-free parts and shipped as a separate helper under the
[LGPL 2.1](Lemon/Licenses/FFmpeg-LGPL-2.1.txt). That build includes LAME and mpg123 (LGPL 2.1) and libvorbis,
libogg, Opus, libvpx and libwebp (BSD licences).

Lemon is an independent project and is not affiliated with Apple or any other app.

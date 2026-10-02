#!/bin/zsh
# Builds Lemon's own LGPL FFmpeg (no GPL or non-free parts) as one self-contained binary.
#
#   Video: Apple VideoToolbox (H.264/HEVC), VP9 (libvpx), MPEG-4, WMV  — no x264/x265 (GPL)
#   Audio: MP3 (LAME + mpg123), Vorbis, Opus, AAC, FLAC, WMA, PCM
#   Image: WebP (libwebp)
#
# Output: Vendor/bin/ffmpeg  (Xcode copies it into Lemon.app/Contents/Helpers and signs it)
# Licence notes for shipping: Vendor/ffmpeg-LICENSE.md (LGPL 2.1) — credit FFmpeg in About.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
VERSION=9.0.2
WORK=$ROOT/Vendor/build
STAGE=$WORK/stage        # static libraries only, so the binary needs nothing from Homebrew
mkdir -p "$WORK" "$STAGE/lib" "$ROOT/Vendor/bin"

echo "▸ Installing build tools and encoder libraries (Homebrew)…"
brew install nasm pkgconf lame mpg123 libogg libvorbis opus libvpx webp

echo "▸ Collecting static libraries…"
for pair in lame:libmp3lame mpg123:libmpg123 libogg:libogg libvorbis:libvorbis libvorbis:libvorbisenc opus:libopus \
            libvpx:libvpx webp:libwebp webp:libwebpmux webp:libsharpyuv; do
  pkg=${pair%%:*} lib=${pair#*:}
  a="$(brew --prefix "$pkg")/lib/$lib.a"
  [[ -f "$a" ]] || { echo "Missing $a"; exit 1; }
  cp -f "$a" "$STAGE/lib/"
done

echo "▸ Downloading FFmpeg $VERSION source…"
cd "$WORK"
[[ -f ffmpeg-$VERSION.tar.xz ]] || curl -fLO "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
rm -rf "ffmpeg-$VERSION" && tar xf "ffmpeg-$VERSION.tar.xz"
cd "ffmpeg-$VERSION"

echo "▸ Configuring (LGPL only)…"
BREW=$(brew --prefix)
./configure \
  --prefix="$WORK/out" \
  --disable-gpl --disable-nonfree \
  --disable-ffplay --disable-ffprobe --disable-doc --disable-debug \
  --disable-network --disable-autodetect \
  --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib --enable-iconv \
  --enable-libmp3lame --enable-libvorbis --enable-libopus --enable-libvpx --enable-libwebp \
  --extra-cflags="-I$BREW/include -mmacosx-version-min=14.0" \
  --extra-ldflags="-L$STAGE/lib -mmacosx-version-min=14.0" \
  --extra-libs="-lmpg123 -liconv" \
  --pkg-config-flags=--static

echo "▸ Building (this takes a while)…"
make -j"$(sysctl -n hw.ncpu)"
cp -f ffmpeg "$ROOT/Vendor/bin/ffmpeg"
cp -f COPYING.LGPLv2.1 "$ROOT/Vendor/ffmpeg-LICENSE.md"

echo "▸ Checking it uses only macOS system libraries…"
otool -L "$ROOT/Vendor/bin/ffmpeg" | tail -n +2
if otool -L "$ROOT/Vendor/bin/ffmpeg" | grep -q "$BREW"; then echo "✗ Links to Homebrew"; exit 1; fi
"$ROOT/Vendor/bin/ffmpeg" -hide_banner -version | head -3
echo "✓ Vendor/bin/ffmpeg ready"

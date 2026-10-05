#!/bin/zsh
# Compiles Lemon's engines with a test program and runs every conversion route and tool.
# Results go to build/engine-tests/ (open it to look at the files).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/engine-tests
mkdir -p build
SOURCES=(Lemon/Core/{FileKind,OutputFormat,Tool,ActionCatalog,SafeSaver,Settings,Jobs,Practice}.swift Lemon/Engines/*.swift Lemon/Tools/*.swift)
xcrun swiftc -O -o build/engine-tests-bin Tests/EngineTests/main.swift "${SOURCES[@]}" 2>&1 | grep -E "error" || true
LEMON_FFMPEG="$PWD/Vendor/bin/ffmpeg" build/engine-tests-bin "$PWD/$OUT"

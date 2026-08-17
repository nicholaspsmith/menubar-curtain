#!/usr/bin/env bash
# Render the app icon from scripts/make-icon.swift into Resources/bundle/Curtain.icns.
# The bundler copies Resources/bundle/ into the .app, and Info.plist points at it.
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Drawing master"
swift scripts/make-icon.swift "$WORK/master.png" >/dev/null

echo "==> Building iconset"
SET="$WORK/Curtain.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/master.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/master.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> Packing .icns"
mkdir -p Resources/bundle
iconutil --convert icns "$SET" --output Resources/bundle/Curtain.icns
echo "==> Wrote Resources/bundle/Curtain.icns"

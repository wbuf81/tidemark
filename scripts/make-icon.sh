#!/bin/bash
# Renders Resources/icon/*.svg and builds Resources/Tidemark.icns. Run from anywhere; idempotent.
# Needs only macOS tools: sips (or qlmanage as a fallback) and iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."
src=Resources/icon
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

raster() { # svg size out.png
  if sips -s format png -z "$2" "$2" "$1" --out "$3" >/dev/null 2>&1 && [ -s "$3" ]; then :; else
    qlmanage -t -s "$2" -o "$work" "$1" >/dev/null 2>&1
    mv "$work/$(basename "$1").png" "$3"
  fi
}

raster "$src/tidemark.svg" 1024 "$work/master.png"
# sips -z on an SVG may keep its own size; make sure the master is 1024.
sips -z 1024 1024 "$work/master.png" >/dev/null
raster "$src/tidemark-32.svg" 64 "$work/s64.png";  sips -z 64 64 "$work/s64.png" >/dev/null
raster "$src/tidemark-32.svg" 32 "$work/s32.png";  sips -z 32 32 "$work/s32.png" >/dev/null
raster "$src/tidemark-16.svg" 32 "$work/s16x2.png"; sips -z 32 32 "$work/s16x2.png" >/dev/null
raster "$src/tidemark-16.svg" 16 "$work/s16.png";  sips -z 16 16 "$work/s16.png" >/dev/null

set_dir="$work/Tidemark.iconset"
mkdir "$set_dir"
cp "$work/s16.png"    "$set_dir/icon_16x16.png"
cp "$work/s16x2.png"  "$set_dir/icon_16x16@2x.png"
cp "$work/s32.png"    "$set_dir/icon_32x32.png"
cp "$work/s64.png"    "$set_dir/icon_32x32@2x.png"
for s in 128 256 512; do
  sips -z $s $s "$work/master.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$work/master.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/Tidemark.icns
echo "Wrote Resources/Tidemark.icns"

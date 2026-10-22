#!/bin/bash
# Draws the README's pictures from the render mode (demo data, the fixed render moment) and puts
# them in docs/images: <name>-light.png, <name>-dark.png and widget-status.gif. Run from anywhere;
# re-run it after any UI change. No app is launched and nothing is captured from the screen.
# Needs swift, sips (macOS) and ffmpeg (Homebrew: brew install ffmpeg) for the GIF.
set -euo pipefail
cd "$(dirname "$0")/.."

FFMPEG=${FFMPEG:-$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)}
OUT=docs/images
NAMES="hero step-download step-not-opened step-open-anyway step-reads step-plan-limits step-widget"
MAX_WIDTH=1760   # pixels: 880 points at 2x, the hero's width

tmp=$(mktemp -d)
cleanup() { find "$tmp" -mindepth 1 -delete; rmdir "$tmp"; }
trap cleanup EXIT

swift run Tidemark --render "$tmp" >/dev/null

mkdir -p "$OUT"
for name in $NAMES; do
  for look in light dark; do
    src="$tmp/readme-$name-$look.png"
    [ -s "$src" ] || { echo "missing $src" >&2; exit 1; }
    dest="$OUT/$name-$look.png"
    cp "$src" "$dest"
    width=$(sips -g pixelWidth "$dest" | awk '/pixelWidth/ {print $2}')
    if [ "$width" -gt "$MAX_WIDTH" ]; then sips --resampleWidth "$MAX_WIDTH" "$dest" >/dev/null; fi
  done
done

# The status GIF (light only): one rendered frame per status, each held 1.5 seconds, drawn at
# 12 frames a second with its own palette, 900 pixels wide, looping forever.
if [ -x "$FFMPEG" ]; then
  "$FFMPEG" -y -loglevel error -start_number 0 -framerate 2/3 -i "$tmp/readme-gif-%d-light.png" \
    -vf "fps=12,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none" \
    -loop 0 "$OUT/widget-status.gif"
else
  echo "ffmpeg not found: skipped widget-status.gif" >&2
fi

echo "Wrote the README's pictures to $OUT"

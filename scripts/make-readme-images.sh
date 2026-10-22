#!/bin/bash
# Draws the README's pictures from the render mode (demo data, the fixed render moment) and puts
# them in docs/images: <name>-light.png, <name>-dark.png, widget-status.gif and click-a-plan.gif.
# Run from anywhere; re-run it after any UI change. No app is launched and nothing is captured from the screen.
# Needs swift, sips (macOS) and ffmpeg (Homebrew: brew install ffmpeg) for the GIFs.
set -euo pipefail
cd "$(dirname "$0")/.."

FFMPEG=${FFMPEG:-$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)}
OUT=docs/images
FEATURES="tide status battery details usage week report trends notch private"
STEPS="step-download step-not-opened step-open-anyway step-reads step-plan-limits step-widget"
HERO_WIDTH=1960   # pixels: 980 points at 2x
STEP_WIDTH=1760   # pixels: 880 points at 2x

tmp=$(mktemp -d)
cleanup() { find "$tmp" -mindepth 1 -delete; rmdir "$tmp"; }
trap cleanup EXIT

swift run Tidemark --render "$tmp" >/dev/null

mkdir -p "$OUT"
# copy <render name> <file name> <max width in pixels>
copy() {
  for look in light dark; do
    src="$tmp/readme-$1-$look.png"
    [ -s "$src" ] || { echo "missing $src" >&2; exit 1; }
    dest="$OUT/$2-$look.png"
    cp "$src" "$dest"
    width=$(sips -g pixelWidth "$dest" | awk '/pixelWidth/ {print $2}')
    if [ "$width" -gt "$3" ]; then sips --resampleWidth "$3" "$dest" >/dev/null; fi
  done
}
copy hero hero "$HERO_WIDTH"
for name in $STEPS; do copy "$name" "$name" "$STEP_WIDTH"; done
for name in $FEATURES; do copy "feature-$name" "feature-$name" "$STEP_WIDTH"; done

# The GIFs (light only), each with its own palette, looping forever.
if [ -x "$FFMPEG" ]; then
  # Status: one rendered frame per status, each held 1.5 seconds, 12 frames a second, 900 pixels wide.
  "$FFMPEG" -y -loglevel error -start_number 0 -framerate 2/3 -i "$tmp/readme-gif-%d-light.png" \
    -vf "fps=12,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none" \
    -loop 0 "$OUT/widget-status.gif"
  # Click a plan: the widget alone for 1.5 seconds, then its details card open for 2.5, 640 pixels wide.
  list="$tmp/click.txt"
  {
    echo "file '$tmp/readme-click-0-light.png'"; echo "duration 1.5"
    echo "file '$tmp/readme-click-1-light.png'"; echo "duration 1.25"
    echo "file '$tmp/readme-click-1-light.png'"   # concat ignores the last entry's duration: its repeat takes the same, so 2 x 1.25 s
  } > "$list"
  "$FFMPEG" -y -loglevel error -f concat -safe 0 -i "$list" \
    -vf "fps=4,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
    -loop 0 "$OUT/click-a-plan.gif"
else
  echo "ffmpeg not found: skipped the GIFs" >&2
fi

echo "Wrote the README's pictures to $OUT"

#!/bin/bash
# Builds build/Tidemark.app: a release binary in a minimal bundle, versioned from VERSION.
# Signed with $TIDEMARK_SIGN_IDENTITY when set, else ad-hoc.
# Universal (Apple Silicon + Intel) when the toolchain can cross-compile, else native only;
# TIDEMARK_REQUIRE_UNIVERSAL=1 fails instead of skipping an architecture.
# TIDEMARK_OUT changes the output folder (default build); release.sh uses it.
set -euo pipefail
cd "$(dirname "$0")"

OUT="${TIDEMARK_OUT:-build}"
APP="$OUT/Tidemark.app"
VERSION="$(tr -d '[:space:]' < VERSION)"

# Everything is compiled and assembled in a staging folder first. Only when that has worked is a
# copy of THIS app running from the output folder quit and the bundle swapped in, so a failed
# compile leaves the running app alone. No other app is touched.
STAGE="$OUT/.staging"
STAGED="$STAGE/Tidemark.app"
rm -rf "$STAGE"
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources"

binaries=()
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx14.0"
  if swift build -c release --triple "$triple" --product Tidemark; then
    # Every triple shares one output folder, so copy each binary out before the next build.
    cp "$(swift build -c release --triple "$triple" --show-bin-path)/Tidemark" "$STAGE/Tidemark-$arch"
    binaries+=("$STAGE/Tidemark-$arch")
  elif [ "$arch" = "$(uname -m)" ] || [ "${TIDEMARK_REQUIRE_UNIVERSAL:-0}" = 1 ]; then
    echo "Build failed for $arch" >&2; exit 1
  else
    echo "Skipping $arch (cross-compiling isn't available here)"
  fi
done
lipo -create "${binaries[@]}" -output "$STAGED/Contents/MacOS/Tidemark"
rm -f "${binaries[@]}"

scripts/write-info-plist.sh "$STAGED/Contents/Info.plist" "$VERSION"
cp Resources/Tidemark.icns "$STAGED/Contents/Resources/Tidemark.icns"
cp LICENSE "$STAGED/Contents/Resources/LICENSE"

# Signed with $TIDEMARK_SIGN_IDENTITY when set, else ad-hoc. The designated requirement is the
# bundle id, so macOS keeps privacy permissions (like notifications) across rebuilds instead of
# tying them to each build's hash. With a signing identity it also pins that certificate, so a
# look-alike app with the same id but another signature doesn't inherit the permissions.
identity="${TIDEMARK_SIGN_IDENTITY:--}"
req='=designated => identifier "io.github.wbuf81.tidemark"'
if [ "$identity" != "-" ]; then
  if [[ "$identity" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    sha="$(printf '%s' "$identity" | tr '[:lower:]' '[:upper:]')"
  else
    sha="$(security find-certificate -c "$identity" -Z 2>/dev/null | awk '/^SHA-1 hash:/ { print $3; exit }')"
  fi
  [ -n "$sha" ] || { echo "Can't find the certificate for signing identity '$identity'" >&2; exit 1; }
  req="=designated => identifier \"io.github.wbuf81.tidemark\" and certificate leaf = H\"$sha\""
fi
codesign --force --sign "$identity" --requirements "$req" "$STAGED"

# Compiled and signed: now quit a copy of this app running from the output folder and swap it in.
running="$PWD/$APP/Contents/MacOS/Tidemark"
reopen=0
if pgrep -f "$running" >/dev/null; then
  pkill -f "$running" || true
  reopen=1
fi
rm -rf "$APP"
mv "$STAGED" "$APP"
rm -rf "$STAGE"
echo "Built $APP ($VERSION)"
if [ "$reopen" = 1 ]; then
  open "$APP"
  echo "Reopened the running copy"
fi

#!/bin/bash
# Builds a universal Tidemark.app and packages it: build/release/Tidemark-<version>.zip plus its
# .sha256. Not notarized. Signs with $TIDEMARK_SIGN_IDENTITY when set, else ad-hoc.
# --dry-run prints the plan and does nothing else.
set -euo pipefail
cd "$(dirname "$0")"

dry=0
case "${1:-}" in
  --dry-run) dry=1;;
  '') ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2;;
esac

VERSION="$(tr -d '[:space:]' < VERSION)"
OUT="${TIDEMARK_OUT:-build/release}"
APP="$OUT/Tidemark.app"
ZIP="$OUT/Tidemark-$VERSION.zip"
IDENTITY="${TIDEMARK_SIGN_IDENTITY:--}"
[ "$IDENTITY" = "-" ] && signing="ad-hoc" || signing="$IDENTITY"

if [ "$dry" = 1 ]; then
  cat <<PLAN
Release plan for Tidemark $VERSION (dry run: nothing is built or written)
  1. swift build -c release --triple arm64-apple-macosx14.0 --product Tidemark
  2. swift build -c release --triple x86_64-apple-macosx14.0 --product Tidemark
  3. lipo -create the two binaries into $APP/Contents/MacOS/Tidemark (fails if either is missing)
  4. Stamp Info.plist $VERSION, add the icon and LICENSE, sign ($signing)
  5. ditto -c -k --keepParent $APP $ZIP
  6. Write $ZIP.sha256
  7. Print codesign -dv and lipo -archs
Not notarized.
PLAN
  exit 0
fi

# build.sh builds each architecture with --triple and joins them with lipo; here neither may be skipped.
TIDEMARK_OUT="$OUT" TIDEMARK_REQUIRE_UNIVERSAL=1 ./build.sh

archs="$(lipo -archs "$APP/Contents/MacOS/Tidemark")"
for a in arm64 x86_64; do
  case " $archs " in *" $a "*) ;; *) echo "Missing architecture $a (have: $archs)" >&2; exit 1;; esac
done

codesign --verify --strict "$APP"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "Tidemark-$VERSION.zip" > "Tidemark-$VERSION.zip.sha256")

codesign -dv "$APP" 2>&1 || true
echo "Architectures: $archs"
echo "Wrote $ZIP"
cat "$ZIP.sha256"

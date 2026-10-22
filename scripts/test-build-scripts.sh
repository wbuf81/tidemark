#!/bin/bash
# Tests the version stamping and the release script's dry run. Builds nothing, touches no Keychain.
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
check() { if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: wanted '$2', got '$1'"; fails=$((fails+1)); fi; }
has() { if grep -qF -- "$2" <<<"$1"; then echo "ok   $3"; else echo "FAIL $3: missing '$2'"; fails=$((fails+1)); fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# VERSION file
check "$(tr -d '[:space:]' < VERSION 2>/dev/null)" "1.0.0" "VERSION is 1.0.0"

# Info.plist stamping
scripts/write-info-plist.sh "$tmp/Info.plist" 9.8.7 >/dev/null 2>&1
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$tmp/Info.plist" 2>/dev/null; }
check "$(plutil -lint "$tmp/Info.plist" >/dev/null 2>&1; echo $?)" "0" "plist is valid"
check "$(pb CFBundleShortVersionString)" "9.8.7" "short version stamped"
check "$(pb CFBundleVersion)" "9.8.7" "bundle version stamped"
check "$(pb CFBundleIconFile)" "Tidemark" "icon file named"
check "$(pb CFBundleIdentifier)" "io.github.wbuf81.tidemark" "bundle id kept"
check "$(pb LSUIElement)" "true" "agent app flag kept"
check "$(pb CFBundleInfoDictionaryVersion)" "6.0" "info dictionary version named"
check "$(pb NSHumanReadableCopyright | grep -c "Public domain")" "1" "About panel has a copyright line"

# build.sh wiring (read, never run)
b="$(cat build.sh)"
has "$b" "write-info-plist.sh" "build.sh uses the plist script"
has "$b" "VERSION" "build.sh reads VERSION"
has "$b" "Resources/Tidemark.icns" "build.sh copies the icon"
has "$b" "LICENSE" "build.sh copies LICENSE"
has "$b" "TIDEMARK_SIGN_IDENTITY" "build.sh honors the signing identity"
has "$b" 'identifier "io.github.wbuf81.tidemark"' "designated requirement kept"
has "$b" 'certificate leaf = H' "signing identity pins the certificate"
has "$b" '.staging' "build.sh stages before swapping"
# build.sh compiles (the first `swift build`) before it quits anything or removes the old bundle
first_swift=$(grep -n 'swift build' build.sh | head -1 | cut -d: -f1)
first_quit=$(grep -n 'pkill' build.sh | head -1 | cut -d: -f1)
first_rm=$(grep -n 'rm -rf "\$APP"' build.sh | head -1 | cut -d: -f1)
if [ -n "$first_swift" ] && [ "$first_swift" -lt "${first_quit:-0}" ] && [ "$first_swift" -lt "${first_rm:-0}" ]; then
  echo "ok   build.sh compiles before it quits or replaces anything"
else echo "FAIL build.sh compiles before it quits or replaces anything"; fails=$((fails+1)); fi

# release.sh dry run
snap() { if [ -e build ]; then find build -print0 | sort -z | xargs -0 stat -f '%N %m %z' 2>/dev/null; else echo missing; fi; }
before="$(snap)"
dryout="$tmp/dry-out"
out="$(TIDEMARK_OUT="$dryout" scripts/../release.sh --dry-run 2>&1)"; rc=$?
check "$rc" "0" "dry run exits 0"
has "$out" "Tidemark-1.0.0.zip" "plan names the zip"
has "$out" "Tidemark-1.0.0.zip.sha256" "plan names the checksum"
has "$out" "arm64" "plan builds arm64"
has "$out" "x86_64" "plan builds x86_64"
has "$out" "lipo -create" "plan joins with lipo"
has "$out" "ditto -c -k --keepParent" "plan zips with ditto"
if [ -e "$dryout" ]; then echo "FAIL dry run created its output folder"; fails=$((fails+1)); else echo "ok   dry run created nothing"; fi
check "$(snap)" "$before" "dry run left build/ as it was"
for t in "cask template has version placeholder:@VERSION@" "cask template has sha placeholder:@SHA256@"; do
  has "$(cat scripts/tidemark-cask.rb.template 2>/dev/null)" "${t#*:}" "${t%%:*}"
done
has "$(cat scripts/make-signing-cert.sh 2>/dev/null)" "Tidemark Local Signing" "cert script names the certificate"

[ "$fails" = 0 ] && echo "All build-script tests passed" || { echo "$fails failed"; exit 1; }

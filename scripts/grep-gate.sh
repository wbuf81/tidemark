#!/bin/bash
# The last check before anything is published. Usage: grep-gate.sh <dir> <private-patterns-file>
# Fails (exit 1) on, in any text file under <dir> and in every file name under it:
#   - a line matching any entry in the private-patterns file (fixed strings, any case, exactly as the
#     commit guard reads the same list; blank lines and lines starting with # are ignored)
#   - an email, a /Users/ path or an 8-4-4-4-12 UUID that isn't covered by the guard's allow list
#     (.githooks/allow-patterns.sh, the one definition both share)
# Exits 2 if grep itself fails (a gate that can't look must not say "clean").
# The private-patterns file is the caller's own; this script never looks for one.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../.githooks/allow-patterns.sh
. "$here/../.githooks/allow-patterns.sh"

if [ $# -ne 2 ]; then echo "usage: grep-gate.sh <dir> <private-patterns-file>" >&2; exit 2; fi
dir="$1"; pfile="$2"
[ -d "$dir" ] || { echo "grep-gate: not a folder: $dir" >&2; exit 2; }
[ -r "$pfile" ] || { echo "grep-gate: can't read the patterns file: $pfile" >&2; exit 2; }

found=0
report() { found=1; printf '  %s\n' "$*" >&2; }
die() { echo "grep-gate: grep failed ($*); can't vouch for this tree" >&2; exit 2; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
clean="$work/patterns"; out="$work/out"; paths="$work/paths"
grep -Ev '^[[:space:]]*(#|$)' "$pfile" > "$clean"; [ $? -le 1 ] || die "reading the patterns"

(cd "$dir" && find . -mindepth 1 -not -path './.git/*' | sed 's|^\./||') > "$paths" || die "listing files"

# 1. private patterns, in file contents and in file names
if [ -s "$clean" ]; then
  grep -rIinF -f "$clean" "$dir" > "$out"; rc=$?
  [ "$rc" -le 1 ] || die "private patterns, exit $rc"
  while IFS= read -r hit; do report "private pattern: $hit"; done < "$out"
  grep -inF -f "$clean" "$paths" > "$out"; rc=$?
  [ "$rc" -le 1 ] || die "private patterns in names, exit $rc"
  while IFS= read -r hit; do report "file name matches a private word: ${hit#*:}"; done < "$out"
fi

# check LABEL REGEX: report each matched piece (in contents, then in file names) the allow list doesn't cover
check() {
  local label="$1" re="$2" line piece rc
  grep -rIHoiE -e "$re" "$dir" > "$out"; rc=$?
  [ "$rc" -le 1 ] || die "$label, exit $rc"
  while IFS= read -r line; do
    piece="${line#*:}"            # drop "file:"
    [ "$label" = "home path" ] && piece="${piece%/}/"
    printf '%s\n' "$piece" | grep -Eiq -e "$allow" && continue
    report "$label: $line"
  done < "$out"
  grep -oiE -e "$re" "$paths" > "$out"; rc=$?
  [ "$rc" -le 1 ] || die "$label in names, exit $rc"
  while IFS= read -r piece; do
    [ "$label" = "home path" ] && piece="${piece%/}/"
    printf '%s\n' "$piece" | grep -Eiq -e "$allow" && continue
    report "$label in a file name: $piece"
  done < "$out"
}

check "email" '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
check "home path" '/Users/[A-Za-z0-9._-]+/?'
check "uuid" '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

if [ "$found" -ne 0 ]; then echo "grep-gate: FAILED" >&2; exit 1; fi
echo "grep-gate: clean"

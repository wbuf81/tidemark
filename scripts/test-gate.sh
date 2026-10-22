#!/bin/bash
# Tests the public-export gate (grep-gate.sh) and the exporter (export-public.sh) on temp trees.
# It writes its own private-patterns file; it never reads .git/info/sensitive-patterns.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
gate="$here/grep-gate.sh"
export_sh="$here/export-public.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

patterns="$work/patterns.txt"
printf '# a comment\n\nzebrafish-secret\nHarbor Private\n' > "$patterns"

# expect_clean NAME LINE: a one-line tree that must pass.  expect_blocked: must fail.
tree() { rm -rf "$work/t"; mkdir -p "$work/t/Sources"; printf '%s\n' "$1" > "$work/t/Sources/a.swift"; }
expect_clean()   { tree "$2"; if "$gate" "$work/t" "$patterns" >/dev/null 2>&1; then pass "$1"; else fail "$1 (should pass)"; fi; }
expect_blocked() { tree "$2"; if "$gate" "$work/t" "$patterns" >/dev/null 2>&1; then fail "$1 (should fail)"; else pass "$1"; fi; }

# Planted values are built from pieces so this file itself passes the guard hooks.
at='@'; users='/Users'; dash='-'
uuid_up="1B4E28BA${dash}2FA1${dash}11D2${dash}883F${dash}0016D3CCA427"
uuid_lo="1b4e28ba${dash}2fa1${dash}11d2${dash}883f${dash}0016d3cca427"
store_id="8AD323F0${dash}8465${dash}42C6${dash}98BD${dash}6E670027E1DC"

# The gate
expect_clean   "clean line"                    'let name = "Tidemark"'
expect_blocked "private pattern"               'the zebrafish-secret project'
expect_blocked "private pattern, other case"   'ZEBRAFISH-SECRET'
expect_blocked "private pattern with space"    'see Harbor Private notes'
expect_clean   "comment and blank lines in the patterns file match nothing" 'a comment about nothing'
expect_blocked "email"                         "mail me at someone${at}corp.test"
expect_clean   "github noreply email"          "123+x${at}users.noreply.github.com"
expect_clean   "anthropic noreply email"       "noreply${at}anthropic.com"
expect_blocked "other noreply lookalike"       "noreply${at}other.test"
expect_blocked "home path with a name"         "${users}/someone/Library/x"
expect_clean   "home path /Users/you/"         "${users}/you/Library/x"
expect_blocked "random UUID"                   "$uuid_up"
expect_blocked "random UUID, lower case"       "$uuid_lo"
expect_clean   "the web store UUID"            "$store_id"
expect_clean   "user id like sess-tide-0001"   'sess-tide-0001'
# The guard's allow list, shared by the gate
expect_clean   "retina image name"             'icon_16x16@2x.png'
expect_clean   "example.com email"             "t${at}example.com"
expect_clean   "example.org email"             "t${at}example.org"
expect_blocked "example.net email"             "t${at}example.net"
expect_clean   "zero-prefix UUID"              "00000000${dash}0000${dash}4000${dash}8000${dash}000000000001"
expect_clean   "home path /Users/you (no slash)" "${users}/you"

# The private list is read as fixed strings, and a grep failure is a failure
printf 'Acme(Inc\nzebra-secret [x\n' > "$work/p2.txt"
tree 'we work with Acme(Inc here'
if "$gate" "$work/t" "$work/p2.txt" >/dev/null 2>&1; then fail "pattern with ( matches as text (should fail)"; else pass "pattern with ( matches as text"; fi
tree 'only zebra-secret [x here'
if "$gate" "$work/t" "$work/p2.txt" >/dev/null 2>&1; then fail "pattern with [ matches as text (should fail)"; else pass "pattern with [ matches as text"; fi
tree 'nothing to see'
"$gate" "$work/t" "$work/p2.txt" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "odd patterns, clean tree passes" || fail "odd patterns, clean tree passes (exit $rc)"
tree 'zebrafish-secret'; chmod 000 "$work/t/Sources/a.swift"
"$gate" "$work/t" "$patterns" >/dev/null 2>&1; rc=$?
chmod 644 "$work/t/Sources/a.swift"
[ "$rc" -eq 2 ] && pass "unreadable file: exit 2, never clean" || fail "unreadable file: exit 2, never clean (exit $rc)"

# File names are checked too
tree 'clean'; touch "$work/t/zebrafish-secret.jpg"
if "$gate" "$work/t" "$patterns" >/dev/null 2>&1; then fail "private word in a file name (should fail)"; else pass "private word in a file name"; fi
tree 'clean'; touch "$work/t/someone${at}corp.test.png"
if "$gate" "$work/t" "$patterns" >/dev/null 2>&1; then fail "email in a file name (should fail)"; else pass "email in a file name"; fi
tree 'clean'; touch "$work/t/${users}-someone-x.txt"; mkdir -p "$work/t/a${users}/someone"; touch "$work/t/a${users}/someone/x"
if "$gate" "$work/t" "$patterns" >/dev/null 2>&1; then fail "home path in a file name (should fail)"; else pass "home path in a file name"; fi
tree 'clean'; touch "$work/t/icon_32x32@2x.png"
if "$gate" "$work/t" "$patterns" >/dev/null 2>&1; then pass "retina file name passes"; else fail "retina file name passes (should pass)"; fi

# A planted string in a nested file, and a hidden file
tree 'clean'; mkdir -p "$work/t/deep/er"; echo 'zebrafish-secret' > "$work/t/deep/er/.hidden"
if "$gate" "$work/t" "$patterns" >/dev/null 2>&1; then fail "hidden nested file (should fail)"; else pass "hidden nested file"; fi
# Wrong usage
if "$gate" "$work/t" >/dev/null 2>&1; then fail "missing patterns file (should fail)"; else pass "missing patterns file"; fi
if "$gate" "$work/t" "$work/nope.txt" >/dev/null 2>&1; then fail "unreadable patterns file (should fail)"; else pass "unreadable patterns file"; fi

# The exporter, on a throwaway repo
repo="$work/repo"; out="$work/out"
mkdir -p "$repo/Sources/X" "$repo/scripts" "$repo/docs/images" "$repo/.github/workflows" "$repo/release" "$repo/docs/superpowers"
echo a > "$repo/Sources/X/a.swift"; echo b > "$repo/scripts/export-allowlist.txt"
echo c > "$repo/docs/contracts.md"; echo d > "$repo/docs/images/x-light.png"; echo d > "$repo/docs/images/x-dark.png"; echo d > "$repo/docs/images/README-pictures.txt"
echo d > "$repo/docs/images/hero-light.jpg"; echo d > "$repo/docs/images/crab-moods.gif"; echo d > "$repo/docs/images/notch.png"; echo d > "$repo/docs/images/x.png"; echo e > "$repo/.github/workflows/ci.yml"
echo f > "$repo/README.md"; echo g > "$repo/release/PLAN.md"; echo h > "$repo/docs/superpowers/plan.md"
echo i > "$repo/NOTES.md"; echo j > "$repo/.gitignore"
cp "$here/export-allowlist.txt" "$repo/scripts/export-allowlist.txt"
git -C "$repo" init -q && git -C "$repo" add -A \
  && git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m t
(cd "$repo" && "$export_sh" HEAD "$out") >/dev/null 2>&1 || fail "export runs"
for keep in Sources/X/a.swift scripts/export-allowlist.txt docs/contracts.md docs/images/x-light.png docs/images/x-dark.png docs/images/README-pictures.txt .github/workflows/ci.yml README.md .gitignore; do
  [ -f "$out/$keep" ] && pass "export keeps $keep" || fail "export keeps $keep"
done
for drop in release/PLAN.md docs/superpowers/plan.md NOTES.md docs/images/hero-light.jpg docs/images/crab-moods.gif docs/images/notch.png docs/images/x.png; do
  [ -e "$out/$drop" ] && fail "export drops $drop" || pass "export drops $drop"
done
[ -d "$out/release" ] && fail "export leaves no empty folders" || pass "export leaves no empty folders"
if (cd "$repo" && "$export_sh" HEAD "$out") >/dev/null 2>&1; then fail "export refuses a non-empty folder (should fail)"; else pass "export refuses a non-empty folder"; fi

# End to end: export this repo's HEAD and run the gate on it with an empty private list.
root="$(cd "$here/.." && pwd)"
real="$work/real"; : > "$work/empty.txt"
if (cd "$root" && "$export_sh" HEAD "$real") >/dev/null 2>&1; then
  if "$gate" "$real" "$work/empty.txt" >"$work/real.log" 2>&1; then pass "gate passes on an export of HEAD"
  else fail "gate passes on an export of HEAD"; sed 's/^/     /' "$work/real.log"; fi
  ls "$real"/docs/images/*.jpg "$real"/docs/images/*.gif >/dev/null 2>&1 && fail "export of HEAD has no old pictures" || pass "export of HEAD has no old pictures"
else fail "export of HEAD runs"; fi

if [ "$fails" -eq 0 ]; then echo "All gate tests passed."; else echo "$fails gate test(s) failed."; exit 1; fi

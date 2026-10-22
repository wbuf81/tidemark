#!/bin/bash
# Usage: export-public.sh <commit> <out-dir>
# Writes the commit's files to <out-dir> (empty or new), keeping only what
# scripts/export-allowlist.txt allows. Run grep-gate.sh on the result before publishing.
set -euo pipefail

if [ $# -ne 2 ]; then echo "usage: export-public.sh <commit> <out-dir>" >&2; exit 2; fi
commit="$1"; out="$2"

mkdir -p "$out"
if [ -n "$(ls -A "$out")" ]; then echo "export-public: $out is not empty" >&2; exit 1; fi

git archive "$commit" | tar -x -C "$out"

allowlist="$out/scripts/export-allowlist.txt"
[ -f "$allowlist" ] || { echo "export-public: the commit has no scripts/export-allowlist.txt" >&2; exit 1; }
globs=()
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  globs+=("${line//\*\*/*}")
done < "$allowlist"

kept=0; dropped=0
while IFS= read -r -d '' f; do
  rel="${f#"$out"/}"
  ok=0
  for g in "${globs[@]}"; do
    # shellcheck disable=SC2254
    case "$rel" in $g) ok=1; break ;; esac
  done
  if [ "$ok" -eq 1 ]; then kept=$((kept + 1)); else rm -f "$f"; dropped=$((dropped + 1)); fi
done < <(find "$out" \( -type f -o -type l \) -print0)

find "$out" -mindepth 1 -type d -empty -delete 2>/dev/null || true
find "$out" -mindepth 1 -type d -empty -delete 2>/dev/null || true
echo "export-public: kept $kept files, dropped $dropped, in $out"

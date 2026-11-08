#!/usr/bin/env bash
#
# sync-repos-tags.sh — keep the `tag` column of tools/repos.txt in step with
# the published index.
#
# `index/index` is the authoritative record of what is published: refresh-index.sh
# resolves each remote's highest `v*` tag. repos.txt is the human-maintained
# manifest (descriptions live there), so its tag column is derived, not typed.
#
# Usage:
#   tools/sync-repos-tags.sh                 # rewrite drifted tag cells
#   tools/sync-repos-tags.sh --check         # report drift, exit 1, write nothing
#   tools/sync-repos-tags.sh [--check] <index-file> <manifest>
#
# Defaults: the `index` file one level up (this script's parent is the index
# repository root) and tools/repos.txt beside this script.
# Rows absent from the index (hashmap, dict, index itself) keep their current
# value; a non-`-` tag on such a row is reported because the index cannot
# confirm it.
#
# The index is space separated (`name version url tag sha256:...`), the
# manifest is pipe separated (`name|tag|content|description`); the two files
# need different field splitting, so it is done with line-local split() instead
# of one awk -F.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

mode=write
if [ "${1:-}" = "--check" ]; then
    mode=check
    shift
fi

index="${1:-$here/../index}"
manifest="${2:-$here/repos.txt}"

[ -f "$index" ] || { echo "sync-repos-tags: no index file at $index" >&2; exit 1; }
[ -f "$manifest" ] || { echo "sync-repos-tags: no manifest at $manifest" >&2; exit 1; }

# One `name|old|new` line per drift.
drift=$(awk '
    FNR == NR {
        n = split($0, a, " ")
        if (n >= 5 && a[1] !~ /^#/) idx[a[1]] = a[4]
        next
    }
    $0 ~ /^#/ { next }
    {
        n = split($0, f, "|")
        if (n < 2) next
        if ((f[1] in idx) && f[2] != idx[f[1]]) printf "%s|%s|%s\n", f[1], f[2], idx[f[1]]
    }
' "$index" "$manifest")

# Manifest rows the index has no line for, but that still carry a real tag.
unconfirmed=$(awk '
    FNR == NR {
        n = split($0, a, " ")
        if (n >= 5 && a[1] !~ /^#/) idx[a[1]] = 1
        next
    }
    $0 ~ /^#/ { next }
    {
        n = split($0, f, "|")
        if (n < 2) next
        if (!(f[1] in idx) && f[2] != "-") printf "%s|%s\n", f[1], f[2]
    }
' "$index" "$manifest")

if [ -n "$unconfirmed" ]; then
    echo "warn: rows with a tag the index does not confirm (left unchanged):" >&2
    printf '%s\n' "$unconfirmed" | awk -F'|' '{ printf "  %-10s %s\n", $1, $2 }' >&2
fi

if [ -z "$drift" ]; then
    echo "ok: repos.txt tags match $index"
    exit 0
fi

echo "drift:"
printf '%s\n' "$drift" | awk -F'|' '{ printf "  %-10s %s -> %s\n", $1, $2, $3 }'

if [ "$mode" = check ]; then
    echo "sync-repos-tags: --check found drift; run without --check to update" >&2
    exit 1
fi

tmp="$manifest.tmp.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
awk '
    FNR == NR {
        n = split($0, a, " ")
        if (n >= 5 && a[1] !~ /^#/) idx[a[1]] = a[4]
        next
    }
    $0 ~ /^#/ { print; next }
    {
        n = split($0, f, "|")
        if (n >= 2 && (f[1] in idx)) {
            f[2] = idx[f[1]]
            out = f[1]
            for (i = 2; i <= n; i++) out = out "|" f[i]
            print out
            next
        }
        print
    }
' "$index" "$manifest" >"$tmp"
mv "$tmp" "$manifest"
echo "updated: $manifest"

#!/usr/bin/env bash
#
# check-char-host.sh — guard method-name uniqueness per mapping host.
#
# The compiler keys a mapped method by (host, method), and a signature does not
# take part in that key. `char *` is shared by every package, so two packages
# may each add `len()` and both compile fine in isolation: the clash only fires
# at a call site that can see both through its import closure. This script
# fails early instead.
#
# It scans every `*.m.ct` under the repo for `map trait ... for type|namespace
# ... {` blocks, extracts each recipe name, and groups by host. Two checks:
#
#   1. duplicate method name on the same host, printing every file:line;
#   2. a host declared with `const` / `volatile` — the compiler's type key
#      drops those qualifiers, so `const char *` silently collapses onto
#      `char *` and the two declarations become ambiguous.
#
# Hosts are normalized only for grouping (whitespace collapsed, const/volatile
# dropped); the original spelling is kept in messages. `.git` and `.ctbuild`
# are pruned so build copies cannot create phantom duplicates.
#
# Usage:
#   tools/check-char-host.sh
#
# Exit status: 0 when every host is unambiguous, 1 otherwise.
# Runs on macOS /bin/bash 3.2 and needs only awk, sed, sort and find.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# This script lives in `index/tools/`; the packages sit two levels up, in the
# ct-pkg workspace root.
repo="$(cd "$here/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/char-host.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM

records="$tmp/records.tsv"
: > "$records"

while IFS= read -r file; do
    rel="${file#"$repo"/}"
    awk -v file="$rel" '
    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
    }
    inblock {
        if ($0 ~ /^[[:space:]]*}/) { inblock = 0; next }
        if (match($0, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/)) {
            name = $0
            sub(/^[[:space:]]*/, "", name)
            sub(/[[:space:]]*\(.*$/, "", name)
            printf "%s\t%s\t%s\t%s\t%d\t%d\n", \
                host_norm, host_raw, name, file, FNR, has_cv
        }
        next
    }
    /^[[:space:]]*map[[:space:]]+trait[[:space:]]+/ {
        if ($0 !~ /[[:space:]]for[[:space:]]+(type|namespace)[[:space:]]+/) next
        raw = $0
        sub(/^.*[[:space:]]for[[:space:]]+(type|namespace)[[:space:]]+/, "", raw)
        sub(/[[:space:]]*\{.*$/, "", raw)
        host_raw = trim(raw)

        # Normalize: drop qualifiers that the compiler type key drops, then
        # remove whitespace so `char *` and `char*` share a key.
        n = split(host_raw, part, /[[:space:]]+/)
        host_norm = ""
        has_cv = 0
        for (i = 1; i <= n; i++) {
            if (part[i] == "const" || part[i] == "volatile") { has_cv = 1; continue }
            host_norm = host_norm part[i]
        }
        inblock = 1
        next
    }
    ' "$file" >> "$records"
done < <(find "$repo" -type d \( -name .git -o -name .ctbuild \) -prune \
            -o -type f -name '*.m.ct' -print | sort)

total="$(wc -l < "$records" | tr -d ' ')"
hosts="$(cut -f1 "$records" | sort -u | wc -l | tr -d ' ')"

status=0

# 1) A qualified host always folds onto the unqualified one.
badcv="$tmp/qualified.tsv"
awk -F'\t' '$6 == 1 { print $4 ":" $5 "  host: " $2 }' "$records" > "$badcv"
if [ -s "$badcv" ]; then
    printf 'FAIL: const/volatile host declaration (the type key drops the qualifier, so this folds onto the bare host):\n' >&2
    sed 's/^/  /' "$badcv" >&2
    status=1
fi

# 2) Same method name on the same host, regardless of signature.
tab="$(printf '\t')"
if ! sort -t "$tab" -k1,1 -k3,3 "$records" | awk -F'\t' '
    {
        key = $1 "\t" $3
        if (key != prev) {
            if (count > 1) report()
            count = 0
            prev = key
        }
        count++
        rows[count] = "    " $4 ":" $5 "  (" $2 " . " $3 ")"
        host = $2
        meth = $3
    }
    END {
        if (count > 1) report()
        exit (bad ? 1 : 0)
    }
    function report(   i) {
        printf "FAIL: duplicate method name on host %s -> %s\n", host, meth > "/dev/stderr"
        for (i = 1; i <= count; i++) print rows[i] > "/dev/stderr"
        bad = 1
    }
'; then
    status=1
fi

if [ "$status" -ne 0 ]; then
    printf '\n%d methods on %d hosts; failures listed above\n' "$total" "$hosts" >&2
    exit 1
fi

printf 'ok: %d methods on %d hosts, no duplicates\n' "$total" "$hosts"

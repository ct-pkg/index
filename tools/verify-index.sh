#!/usr/bin/env bash
#
# verify-index.sh — replay index rows through a real `ct get`.
#
# `refresh-index.sh` checks the index against the tag trees with the same
# digest algorithm `ct` uses, but it cannot prove that the consumer accepts the
# row. This script does: for each row it creates a throwaway project and
# isolated `HOME` / `CT_HOME`, runs
#
#     ct get --index <index> <publisher>/<name>@<version>
#
# and then compares the digest in the written `ct.lock` with the one in the
# index row. A mismatch means the tag content moved since the row was written
# (or the row is stale), which is exactly the failure a consumer would hit.
#
# Usage:
#   tools/verify-index.sh                    # every row
#   tools/verify-index.sh --name std         # rows of one package
#   tools/verify-index.sh --name std --version 0.3.2
#   tools/verify-index.sh --index <file>     # another index file
#
# Environment:
#   CT_BIN   compiler/driver to run (default `ct`, then `ct-ast`)
#
# Exit status: 0 when every selected row installs and matches, 1 otherwise.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
index_file="$here/index"
names=()
versions=()

while [ $# -gt 0 ]; do
    case "$1" in
        --index)
            [ $# -ge 2 ] || { echo "verify-index: --index needs a path" >&2; exit 2; }
            index_file="$2"; shift 2 ;;
        --name)
            [ $# -ge 2 ] || { echo "verify-index: --name needs a value" >&2; exit 2; }
            names+=("$2"); shift 2 ;;
        --version)
            [ $# -ge 2 ] || { echo "verify-index: --version needs a value" >&2; exit 2; }
            versions+=("$2"); shift 2 ;;
        -h | --help)
            sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "verify-index: unknown argument '$1'" >&2
            exit 2 ;;
    esac
done

case "$index_file" in
    /*) ;;
    *) index_file="$PWD/$index_file" ;;
esac
[ -f "$index_file" ] || { echo "verify-index: no index file at $index_file" >&2; exit 1; }

if [ -n "${CT_BIN:-}" ]; then
    ctbin=$CT_BIN
elif command -v ct >/dev/null 2>&1; then
    ctbin=ct
elif command -v ct-ast >/dev/null 2>&1; then
    ctbin=ct-ast
else
    echo "verify-index: neither 'ct' nor 'ct-ast' is on PATH (set CT_BIN)" >&2
    exit 1
fi

selected() {
    [ "${#names[@]}" -eq 0 ] && return 0
    local want
    for want in "${names[@]}"; do
        [ "$1" = "$want" ] && return 0
    done
    return 1
}

total=0
failed=0
while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    # shellcheck disable=SC2086
    set -- $line
    [ $# -ge 5 ] || continue
    name=$1; version=$2
    if [ $# -ge 6 ]; then
        publisher=$3; url=$4; tag=$5; sha=$6
    else
        publisher="-"; url=$3; tag=$4; sha=$5
    fi
    selected "$name" || continue
    if [ "${#versions[@]}" -gt 0 ]; then
        match=0
        for want in "${versions[@]}"; do
            [ "$version" = "$want" ] && match=1
        done
        [ "$match" = 1 ] || continue
    fi
    if [ "$publisher" = "-" ]; then
        spec="$name"
    else
        spec="$publisher/$name"
    fi

    total=$((total + 1))
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/verify-index.XXXXXX")
    mkdir -p "$tmp/home/.cache" "$tmp/proj"
    if ! ( cd "$tmp/proj" \
            && HOME="$tmp/home" CT_HOME="$tmp/home" \
               "$ctbin" get --index "$index_file" "$spec@$version" ) \
            >"$tmp/out" 2>&1; then
        printf 'FAIL  %-10s %-7s get failed\n' "$name" "$version"
        sed 's/^/        /' "$tmp/out"
        failed=$((failed + 1))
        rm -rf "$tmp"
        continue
    fi

    lockline=$(awk '!/^#/ && NF >= 7 { print; exit }' "$tmp/proj/ct.lock")
    if [ -z "$lockline" ]; then
        printf 'FAIL  %-10s %-7s no v2 row in ct.lock\n' "$name" "$version"
        sed 's/^/        /' "$tmp/out"
        failed=$((failed + 1))
        rm -rf "$tmp"
        continue
    fi
    got=$(printf '%s\n' "$lockline" | awk '{ print $NF }')
    gotname=$(printf '%s\n' "$lockline" | awk '{ print $1 }')
    if [ "$got" != "$sha" ]; then
        printf 'FAIL  %-10s %-7s digest %s != index %s\n' "$name" "$version" "$got" "$sha"
        failed=$((failed + 1))
    elif [ "$publisher" != "-" ] && [ "$gotname" != "$spec" ]; then
        printf 'FAIL  %-10s %-7s lock names %s, row says %s\n' "$name" "$version" "$gotname" "$spec"
        failed=$((failed + 1))
    else
        printf 'ok    %-10s %-7s %s\n' "$name" "$version" "$tag"
    fi
    rm -rf "$tmp"
done <"$index_file"

if [ "$total" -eq 0 ]; then
    echo "verify-index: no rows selected" >&2
    exit 1
fi
if [ "$failed" -ne 0 ]; then
    printf '\n%d of %d row(s) failed\n' "$failed" "$total" >&2
    exit 1
fi
printf '\nok: %d row(s) install and match the index\n' "$total"

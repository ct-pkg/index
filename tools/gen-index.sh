#!/bin/sh
#
# gen-index.sh - add or replace one line in the ct package index.
#
# Usage:  tools/gen-index.sh <index-file> <package-dir> <git-url> <tag>
#
# The line format is the one `ct get --index` reads:
#
#     name version git-url tag sha256:<64 lowercase hex>
#
# The digest must be the one `ct get` computes for the vendored tree, so it is
# the SHA-256 of one stream: for every regular file under the package, sorted
# by its relative path, `path` + newline + the file's bytes. `.git`, `vendor`
# and `.ctcache` are not part of a package and are skipped (Pkg.h.ct
# `sha_collect`).
#
# The package at `tag` and the working tree must be byte-identical; the index
# is only honest if the tag names the same content the digest covers.
set -eu

if [ $# -ne 4 ]; then
    echo "usage: $0 <index-file> <package-dir> <git-url> <tag>" >&2
    exit 2
fi

index=$1
dir=$2
url=$3
tag=$4

if [ ! -f "$dir/ct.pkg" ]; then
    echo "$0: no ct.pkg in '$dir'" >&2
    exit 1
fi

name=$(awk -F= '/^name[ 	]*=/{v=$2; gsub(/^[ 	]+|[ 	]+$/, "", v); print v; exit}' "$dir/ct.pkg")
version=$(awk -F= '/^version[ 	]*=/{v=$2; gsub(/^[ 	]+|[ 	]+$/, "", v); print v; exit}' "$dir/ct.pkg")
if [ -z "$name" ] || [ -z "$version" ]; then
    echo "$0: '$dir/ct.pkg' needs name and version" >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    hash() { sha256sum | awk '{ print $1 }'; }
else
    hash() { shasum -a 256 | awk '{ print $1 }'; }
fi

digest=$(
    cd "$dir" &&
    find . -type f \
        ! -path './.git/*' ! -path './vendor/*' ! -path './.ctcache/*' \
        | sed 's|^\./||' | LC_ALL=C sort |
    while IFS= read -r rel; do
        printf '%s\n' "$rel"
        cat "$rel"
    done | hash
)

touch "$index"
tmp="$index.tmp.$$"
awk -v n="$name" -v v="$version" '$1 != n || $2 != v' "$index" >"$tmp"
printf '%s %s %s %s sha256:%s\n' "$name" "$version" "$url" "$tag" "$digest" >>"$tmp"
mv "$tmp" "$index"

echo "$name $version $tag sha256:$digest"

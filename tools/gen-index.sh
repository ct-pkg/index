#!/bin/sh
#
# gen-index.sh - add or replace one line in the ct package index.
#
# Usage:  tools/gen-index.sh <index-file> <package-dir> <git-url> <tag>
#
# The line format is the one `ct get --index` reads (six fields):
#
#     name version publisher git-url tag sha256:<64 lowercase hex>
#
# `publisher` and `ns-root` are the identity keys the shared store requires
# (`ct` v0.54.0+). A package without them cannot be installed, so this script
# refuses to write a line for it instead of producing one that fails later at
# `pkg_store_commit`.
#
# The digest must be the one `ct get` computes for the stored tree, so it is
# the SHA-256 of one stream: for every regular file under the package, sorted
# by its relative path, `path` + newline + the file's bytes. `.git`, `vendor`
# and `.ctcache` are not part of a package and are skipped (Pkg.h.ct
# `sha_collect`).
#
# The tag must be `v<version>` (the only shape `refresh-index.sh` considers),
# so a drifted manifest is rejected here rather than at the consumer.
set -eu

if [ $# -ne 4 ]; then
    echo "usage: $0 <index-file> <package-dir> <git-url> <tag>" >&2
    exit 2
fi

index=$1
dir=$2
url=$3
tag=$4

die() { printf '%s: %s\n' "$0" "$*" >&2; exit 1; }

if [ ! -f "$dir/ct.pkg" ]; then
    echo "$0: no ct.pkg in '$dir'" >&2
    exit 1
fi

manifest_value() {
    awk -F= -v k="$1" '
        {
            key = $1
            gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key != k) next
            v = $0
            sub(/^[^=]*=/, "", v)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            print v
            exit
        }
    ' "$dir/ct.pkg"
}

name=$(manifest_value name)
version=$(manifest_value version)
publisher=$(manifest_value publisher)
nsroot=$(manifest_value ns-root)

[ -n "$name" ] || die "'$dir/ct.pkg' is missing 'name'"
[ -n "$version" ] || die "'$dir/ct.pkg' is missing 'version'"
[ -n "$publisher" ] || die "'$dir/ct.pkg' is missing 'publisher' (required since ct v0.54)"
[ "$publisher" != local ] || die "'$dir/ct.pkg' uses the reserved publisher 'local'"
[ -n "$nsroot" ] || die "'$dir/ct.pkg' is missing 'ns-root' (required since ct v0.54)"
case "$nsroot" in
    /*) die "'$dir/ct.pkg' has an absolute ns-root '$nsroot'" ;;
esac
case "$nsroot" in
    *..*) die "'$dir/ct.pkg' has an ns-root '$nsroot' containing '..'" ;;
esac
[ -d "$dir/$nsroot" ] || die "'$dir/ct.pkg' ns-root '$nsroot' is not a directory"

[ "$tag" = "v$version" ] \
    || die "'$dir/ct.pkg' says version '$version' but the tag is '$tag' (expected 'v$version')"

case "$publisher" in
    */*) die "publisher '$publisher' must not contain '/'" ;;
esac
case "$name" in
    *' '* | *'/'*) die "name '$name' must not contain whitespace or '/'" ;;
esac

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
printf '%s %s %s %s %s sha256:%s\n' \
    "$name" "$version" "$publisher" "$url" "$tag" "$digest" >>"$tmp"
mv "$tmp" "$index"

echo "$name $version $publisher $tag sha256:$digest"

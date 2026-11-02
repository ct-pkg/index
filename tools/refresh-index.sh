#!/bin/sh
#
# refresh-index.sh - rebuild the whole index from `packages.txt`.
#
# For every `name url` pair the highest `v*` tag is resolved (GNU `sort -V`),
# the tag is cloned, and `gen-index.sh` writes its line. The script runs on
# Linux (the CI runner); `sort -V` is not in the BSD userland.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

: >"$here/index.tmp"
while IFS=' ' read -r name url rest; do
    case "$name" in
        '' | '#'*) continue ;;
    esac
    [ -n "$url" ] || continue
    tag=$(git ls-remote --tags --refs "$url" 'v*' |
        sed 's|.*refs/tags/||' | sort -V | tail -1)
    if [ -z "$tag" ]; then
        echo "refresh-index: '$name' has no v* tag at $url" >&2
        exit 1
    fi
    # `clone --branch <tag>` warns ("is not a commit") when the tag is annotated
    # and only checks out lightweight ones cleanly, so clone the default branch
    # and check the tag out instead: `checkout` peels both shapes. The packages
    # are small, so a full clone is not a cost the nightly run cares about.
    rm -rf "$work/$name"
    git clone --quiet "$url" "$work/$name"
    git -C "$work/$name" -c advice.detachedHead=false checkout --quiet "tags/$tag"
    "$here/tools/gen-index.sh" "$here/index.tmp" "$work/$name" "$url" "$tag" >&2
done <"$here/packages.txt"
mv "$here/index.tmp" "$here/index"

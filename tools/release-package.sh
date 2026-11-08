#!/usr/bin/env bash
#
# release-package.sh — publish an already-committed package tag and refresh the
# ct-pkg index.
#
# Usage:
#   tools/release-package.sh <name> <tag>        e.g. hal-posix v1.0.1
#
# What it does, in order (each step stops the run on failure):
#   1. checks that $STAGING/<name> is a clean git repo and carries <tag>, and
#      that `ct.pkg`'s version matches the tag (v1.0.1 <-> 1.0.1);
#   2. pushes `main` and the tag (token injected per command, never stored);
#   3. rebuilds `index` from `index/packages.txt` with tools/refresh-index.sh
#      (it takes each repository's highest tag, so the new tag must be pushed
#      first);
#   4. commits the index change and pushes it;
#   5. points the `tag` column of <name> in tools/repos.txt at <tag>.
#
# The index holds one line per package: `ct get` picks the *lowest* version
# satisfying the range (MVS), so a stale lower line would keep winning. That is
# why the whole index is rebuilt rather than appended to.
#
# Requirements:
#   - RESTie is not used here; this script only needs git and $GITHUB_TOKEN.
#   - GITHUB_TOKEN (or GH_TOKEN) must be able to push to github.com/ct-pkg.
#     Classic PAT: the `repo` and `workflow` scopes.
#
# Env overrides: ORG (default ct-pkg), STAGING (default ~/vscspace/ct-pkg).

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
ORG="${ORG:-ct-pkg}"
STAGING="${STAGING:-$HOME/vscspace/ct-pkg}"

fail() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok    %s\n' "$1"; }
info() { printf '  ..    %s\n' "$1"; }

[ $# -eq 2 ] || fail "usage: $0 <name> <tag>"
name="$1"
tag="$2"
dir="$STAGING/$name"
index="$STAGING/index"

[ -d "$dir/.git" ] || fail "$dir is not a git repository"
[ -d "$index/.git" ] || fail "$index is not a git repository"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    if [ -n "${GH_TOKEN:-}" ]; then
        GITHUB_TOKEN="$GH_TOKEN"
        export GITHUB_TOKEN
        info "GITHUB_TOKEN unset; using GH_TOKEN"
    else
        fail "set GITHUB_TOKEN (or GH_TOKEN) to a token that may push to $ORG"
    fi
fi

# Push through HTTPS with the token supplied per command; it is never written
# into .git/config.
push_git() {
    local repo="$1"; shift
    GIT_TERMINAL_PROMPT=0 git -C "$repo" \
        -c credential.helper= \
        -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$GITHUB_TOKEN"; }; f' \
        "$@"
}

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
echo "== preflight =="

case "$tag" in
    v[0-9]*) ;;
    *) fail "the tag must look like v1.0.1 (got '$tag')" ;;
esac
want_version="${tag#v}"

have_tag=$(git -C "$dir" tag -l "$tag")
[ -n "$have_tag" ] || fail "tag $tag is missing in $dir; create it with: git -C $dir tag -a $tag -m '...'"

dirty=$(git -C "$dir" status --porcelain)
[ -z "$dirty" ] || fail "$dir has uncommitted changes; commit or stash them first"

pkg_version=$(awk -F= '/^version[ 	]*=/{v=$2; gsub(/^[ 	]+|[ 	]+$/, "", v); print v; exit}' "$dir/ct.pkg")
[ "$pkg_version" = "$want_version" ] \
    || fail "ct.pkg says version = '$pkg_version' but the tag is '$tag'"
ok "$name $tag (ct.pkg version matches)"

# ---------------------------------------------------------------------------
# 2. Push the package branch and tag
# ---------------------------------------------------------------------------
echo
echo "== push $name =="
if push_git "$dir" push origin main 2>&1 | sed 's/^/    /'; then :; else
    fail "pushing $name/main failed (does the token have write access to $ORG?)"
fi
if push_git "$dir" push origin "$tag" 2>&1 | sed 's/^/    /'; then :; else
    fail "pushing $name $tag failed"
fi
ok "$name $tag pushed"

# ---------------------------------------------------------------------------
# 3. Rebuild the index
# ---------------------------------------------------------------------------
echo
echo "== rebuild $ORG/index =="
if ! ( cd "$index" && ./tools/refresh-index.sh ); then
    fail "refresh-index.sh failed (is the new tag visible at github.com/$ORG/$name?)"
fi
ok "index rebuilt"

# ---------------------------------------------------------------------------
# 4. Commit and push the index
# ---------------------------------------------------------------------------
echo
echo "== publish the index =="
if [ -z "$(git -C "$index" status --porcelain index)" ]; then
    info "the index already names $tag; nothing to commit"
else
    git -C "$index" add index
    git -C "$index" commit -q -m "index: $name $tag" || fail "committing the index failed"
    if ! push_git "$index" push origin main 2>&1 | sed 's/^/    /'; then
        fail "pushing the index failed"
    fi
    ok "index committed and pushed"
fi

# ---------------------------------------------------------------------------
# 5. Point repos.txt at the released tag
# ---------------------------------------------------------------------------
echo
echo "== tools/repos.txt =="
tool_manifest="$here/repos.txt"
if [ -f "$tool_manifest" ]; then
    tmp="$tool_manifest.tmp.$$"
    awk -F'|' -v n="$name" -v t="$tag" 'BEGIN{OFS="|"} $1==n && $0 !~ /^#/ {$2=t} {print}' \
        "$tool_manifest" >"$tmp" && mv "$tmp" "$tool_manifest"
    ok "repos.txt: $name -> $tag"
else
    info "no $tool_manifest; skipped"
fi

echo
echo "== done =="
grep "^$name " "$index/index" || true

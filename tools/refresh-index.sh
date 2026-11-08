#!/bin/sh
#
# refresh-index.sh - rebuild `index` from `packages.txt`.
#
# For every `name url` pair the highest `v*` tag is resolved, the tag is
# cloned, and `gen-index.sh` writes its line. No arguments means "refresh the
# work tree only"; git operations are opt-in:
#
#   (no flags)   rewrite ./index, leave it uncommitted
#   --dry-run    print per-package changes and a unified diff; write nothing
#   --commit     rewrite ./index and commit it (the commit contains only `index`)
#   --push       implies --commit, then push HEAD:main over SSH and verify
#
# Tag selection is done with awk instead of GNU `sort -V`, so the script also
# runs on macOS. A repository without a `v*` tag is reported and the run exits
# 1 without touching `index`.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)

usage() {
    cat <<'EOF'
usage: tools/refresh-index.sh [--dry-run] [--commit] [--push]

  (no flags)  refresh ./index only
  --dry-run   show the per-package changes and diff; do not write anything
  --commit    refresh and commit `index` (nothing else is staged)
  --push      refresh, commit, push HEAD:main over SSH, then verify with
              `git ls-remote`; implies --commit, never forces

Push target: $INDEX_PUSH_URL (default git@github.com:ct-pkg/index.git).
Readback / fast-forward check: $INDEX_READ_URL (default `git remote get-url origin`).
Both env overrides exist for testing against a local bare repository.
EOF
}

commit=0
push=0
dry=0
while [ $# -gt 0 ]; do
    case "$1" in
        --commit) commit=1 ;;
        --push) commit=1; push=1 ;;
        --dry-run) dry=1 ;;
        -h | --help) usage; exit 0 ;;
        *)
            printf 'refresh-index: unknown option %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

die() { printf 'refresh-index: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

origin_url=$(git -C "$here" remote get-url origin 2>/dev/null || true)
read_url=${INDEX_READ_URL:-$origin_url}
push_url=${INDEX_PUSH_URL:-git@github.com:ct-pkg/index.git}

# ---------------------------------------------------------------------------
# Preflight: refuse to run on top of unrelated edits.
# ---------------------------------------------------------------------------
if [ "$dry" = 0 ]; then
    [ -d "$here/.git" ] || die "$here is not a git work tree"
    dirty=$(git -C "$here" status --porcelain --untracked-files=all)
    unexpected=$(printf '%s\n' "$dirty" | awk 'NF && $NF != "index"')
    if [ -n "$unexpected" ]; then
        printf 'refresh-index: refusing to run: unexpected work-tree changes\n%s\n' "$unexpected" >&2
        die "commit or stash everything except 'index', then retry"
    fi
    [ -z "$dirty" ] || say "note: 'index' already has uncommitted changes; they are the baseline"
fi

if [ "$push" = 1 ] && [ "$dry" = 0 ]; then
    branch=$(git -C "$here" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ "$branch" = main ] || die "push requires branch 'main' (current: ${branch:-detached HEAD})"
    [ -n "$read_url" ] || die "no read URL: set INDEX_READ_URL or add an 'origin' remote"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/refresh-index.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

old="$work/index.old"
if [ -f "$here/index" ]; then
    cp "$here/index" "$old"
else
    : >"$old"
fi
new="$work/index.new"
: >"$new"

# ---------------------------------------------------------------------------
# Rebuild into $new. Nothing under $here is written until every tag resolved.
# ---------------------------------------------------------------------------
skipped=0
while IFS=' ' read -r name url rest; do
    case "$name" in
        '' | '#'*) continue ;;
    esac
    [ -n "${url:-}" ] || continue

    if ! refs=$(git ls-remote --tags --refs "$url" 'v*' 2>"$work/ls.err"); then
        cat "$work/ls.err" >&2
        die "cannot list tags from $url"
    fi
    # Highest semver tag. `ls-remote` prints "<sha>\t<ref>", so take $2.
    # No `sort -V`: BSD sort on macOS does not have it.
    tag=$(printf '%s\n' "$refs" | awk '
        function key(s,   a, n, i, k) {
            sub(/^v/, "", s)
            n = split(s, a, ".")
            k = 0
            for (i = 1; i <= 3; i++) k = k * 1000000 + (a[i] + 0)
            return k
        }
        NF {
            ref = $2
            sub(/^refs\/tags\//, "", ref)
            if (ref !~ /^v/) next
            k = key(ref)
            if (best == "" || k > bk) { best = ref; bk = k }
        }
        END { if (best != "") print best }
    ')
    if [ -z "$tag" ]; then
        say "skip     $name: no v* tag at $url"
        skipped=$((skipped + 1))
        continue
    fi

    # `clone --branch <tag>` warns ("is not a commit") when the tag is annotated
    # and only checks out lightweight ones cleanly, so clone the default branch
    # and check the tag out instead: `checkout` peels both shapes.
    rm -rf "$work/$name"
    if ! git clone --quiet "$url" "$work/$name" 2>"$work/clone.err"; then
        cat "$work/clone.err" >&2
        die "clone failed for $name ($url)"
    fi
    if ! git -C "$work/$name" -c advice.detachedHead=false checkout --quiet "tags/$tag" \
            2>"$work/checkout.err"; then
        cat "$work/checkout.err" >&2
        die "checkout of $name $tag failed"
    fi
    if ! "$here/tools/gen-index.sh" "$new" "$work/$name" "$url" "$tag" >/dev/null \
            2>"$work/gen.err"; then
        cat "$work/gen.err" >&2
        die "gen-index.sh failed for $name $tag"
    fi
    say "fetched  $name $tag"
done <"$here/packages.txt"

if [ "$skipped" -gt 0 ]; then
    say "aborted: $skipped package(s) have no v* tag; index left untouched"
    exit 1
fi

# ---------------------------------------------------------------------------
# Report old -> new before touching the work tree.
# ---------------------------------------------------------------------------
report="$work/report"
{ cat "$old"; printf '__NEW__\n'; cat "$new"; } | awk '
    $0 == "__NEW__" { phase = 1; next }
    phase == 0 && NF >= 5 {
        ov[$1] = $2; ot[$1] = $4; oh[$1] = $5; seen[$1] = 1
        next
    }
    phase == 1 && NF >= 5 {
        n = $1; nn[n] = 1
        if (!(n in seen)) {
            printf "added    %-10s %s %s %s\n", n, $2, $4, $5
            added++
            next
        }
        if (ov[n] != $2 || ot[n] != $4 || oh[n] != $5) {
            printf "changed  %-10s %s -> %s\n", n, ov[n], $2
            if (ot[n] != $4) printf "         %-10s tag %s -> %s\n", "", ot[n], $4
            if (oh[n] != $5) printf "         %-10s sha %s -> %s\n", "", oh[n], $5
            changed++
        } else {
            printf "same     %-10s %s %s\n", n, $2, $4
            same++
        }
    }
    END {
        for (n in seen) {
            if (!(n in nn)) { printf "removed  %s\n", n; removed++ }
        }
        printf "summary: %d changed, %d added, %d removed, %d unchanged\n", changed, added, removed, same
    }
' >"$report"
cat "$report"

if cmp -s "$old" "$new"; then
    changed=0
    say "index: no changes"
else
    changed=1
    if [ "$dry" = 1 ]; then
        say "--- diff (current -> regenerated) ---"
        diff -u "$old" "$new" || true
    fi
fi

# ---------------------------------------------------------------------------
# --dry-run stops here: no writes to the repository.
# ---------------------------------------------------------------------------
if [ "$dry" = 1 ]; then
    lines=$(wc -l <"$new" | tr -d ' ')
    say "[dry-run] would write index ($lines lines); no files were modified"
    if [ "$changed" = 1 ]; then
        say "[dry-run] would commit 'index'"
    else
        say "[dry-run] would not commit (index unchanged)"
    fi
    if [ "$push" = 1 ]; then
        say "[dry-run] would push HEAD:main to $push_url (fast-forward only, no force)"
        [ -n "$read_url" ] && say "[dry-run] would verify with git ls-remote $read_url"
    else
        say "[dry-run] would not push"
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Write, commit, push.
# ---------------------------------------------------------------------------
if [ "$changed" = 1 ]; then
    cp "$new" "$here/index"
    if [ "$commit" = 0 ]; then
        say "index updated; run with --commit to commit it"
    fi
fi

if [ "$commit" = 1 ]; then
    if git -C "$here" diff --quiet -- index; then
        say "commit: index already matches HEAD; nothing to commit"
    else
        names=$(awk '/^changed  / { print $2 }' "$report" | tr '\n' ' ' | sed 's/ *$//')
        msg="index: refresh"
        [ -z "$names" ] || msg="index: refresh $names"
        git -C "$here" add index
        git -C "$here" commit --quiet -m "$msg" \
            || die "git commit failed"
        say "commit: $(git -C "$here" rev-parse --short HEAD) $msg"
    fi
fi

if [ "$push" = 1 ]; then
    dirty=$(git -C "$here" status --porcelain --untracked-files=all)
    [ -z "$dirty" ] || die "refusing to push: work tree is dirty:
$dirty"

    remote_sha=$(git ls-remote "$read_url" refs/heads/main | awk '{ print $1 }')
    if [ -n "$remote_sha" ]; then
        git -C "$here" fetch --quiet "$read_url" main \
            || die "cannot fetch main from $read_url"
        if ! git -C "$here" merge-base --is-ancestor "$remote_sha" HEAD; then
            die "remote main ($remote_sha) is not an ancestor of HEAD; refusing a non-fast-forward push"
        fi
    fi

    say "push: $(git -C "$here" rev-parse --short HEAD) -> $push_url main (no force)"
    if ! git -C "$here" push "$push_url" HEAD:main 2>"$work/push.err"; then
        cat "$work/push.err" >&2
        die "push failed; check SSH access with: ssh -T git@github.com"
    fi

    head=$(git -C "$here" rev-parse HEAD)
    after=$(git ls-remote "$read_url" refs/heads/main | awk '{ print $1 }')
    [ "$after" = "$head" ] \
        || die "verification failed: remote main is ${after:-<missing>}, local HEAD is $head"
    say "ok: remote main = $head (verified via $read_url)"
fi

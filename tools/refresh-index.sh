#!/bin/sh
#
# refresh-index.sh - rebuild `index` from `packages.txt`.
#
# For every `name url` pair the highest `v*` tag is resolved, the repository is
# cloned once, the tag is checked out and `gen-index.sh` writes its six-field
# line. No arguments means "refresh the work tree only"; git operations are
# opt-in:
#
#   (no flags)     rewrite ./index, leave it uncommitted
#   --dry-run      print per-package changes and a unified diff; write nothing
#   --commit       rewrite ./index and commit it (the commit contains only it)
#   --push         implies --commit, then push HEAD:main over SSH and verify
#   --all-tags     index every `v*` tag instead of only the newest one
#   --only <names> rebuild only these comma-separated packages; every other
#                  existing row is preserved (used by tools/package.sh so one
#                  release does not depend on the rest of the ecosystem)
#   --allow-rewrite  accept a different digest for an already published
#                    name+version (tags are immutable; this is an escape hatch)
#
# Two guards borrowed from the consumer contract:
#
#   * a line is only written for a tag whose `ct.pkg` carries `publisher` and
#     `ns-root` (the shared-store identity), and whose tag equals `v<version>`;
#   * all versions of one package must share a publisher: the newest tag's
#     publisher wins and older tags that disagree are reported and skipped;
#   * an existing `name version` row may not change its digest. A moved tag
#     means the tree was rewritten, and consumers holding a lock would diverge.
#
# Tag selection is done with awk instead of GNU `sort -V`, so the script also
# runs on macOS. A repository without a `v*` tag is reported and the run exits
# 1 without touching `index`; an older tag that fails validation in
# `--all-tags` mode is reported and skipped, while the newest tag failing is
# always fatal.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)

usage() {
    cat <<'EOF'
usage: tools/refresh-index.sh [--dry-run] [--commit] [--push]
                              [--all-tags] [--allow-rewrite]

  (no flags)     refresh ./index only
  --dry-run      show the per-package changes and diff; do not write anything
  --commit       refresh and commit `index` (nothing else is staged)
  --push         refresh, commit, push HEAD:main over SSH, then verify with
                 `git ls-remote`; implies --commit, never forces
  --all-tags     index every `v*` tag, not just the newest one
  --only <names> rebuild only these comma-separated packages, keeping the
                 other rows untouched
  --allow-rewrite  allow an already indexed name+version to change digest

Environment:
  INDEX_PACKAGES   input list (default <repo>/packages.txt)
  INDEX_FILE       output file (default <repo>/index)
  INDEX_PUSH_URL   push target (default git@github.com:ct-pkg/index.git)
  INDEX_READ_URL   readback URL (default `git remote get-url origin`)
EOF
}

commit=0
push=0
dry=0
all_tags=0
allow_rewrite=0
only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --commit) commit=1 ;;
        --push) commit=1; push=1 ;;
        --dry-run) dry=1 ;;
        --all-tags) all_tags=1 ;;
        --allow-rewrite) allow_rewrite=1 ;;
        --only)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            only=$(printf '%s' "$2" | tr ',' ' ')
            shift
            ;;
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

packages=${INDEX_PACKAGES:-$here/packages.txt}
index_file=${INDEX_FILE:-$here/index}
case "$index_file" in
    /*) ;;
    *) index_file="$here/$index_file" ;;
esac
index_rel=$index_file
case "$index_file" in
    "$here"/*) index_rel=${index_file#"$here"/} ;;
esac

origin_url=$(git -C "$here" remote get-url origin 2>/dev/null || true)
read_url=${INDEX_READ_URL:-$origin_url}
push_url=${INDEX_PUSH_URL:-git@github.com:ct-pkg/index.git}

# ---------------------------------------------------------------------------
# Preflight: refuse to run on top of unrelated edits.
# ---------------------------------------------------------------------------
if [ "$dry" = 0 ]; then
    [ -d "$here/.git" ] || die "$here is not a git work tree"
    [ -f "$packages" ] || die "no package list at $packages"
    dirty=$(git -C "$here" status --porcelain --untracked-files=all)
    unexpected=$(printf '%s\n' "$dirty" | awk -v keep="$index_rel" 'NF && $NF != keep')
    if [ -n "$unexpected" ]; then
        printf 'refresh-index: refusing to run: unexpected work-tree changes\n%s\n' "$unexpected" >&2
        die "commit or stash everything except the index file first; edits under docs/ and tools/ count as unexpected too, because a refresh commit carries only the index"
    fi
    [ -z "$dirty" ] || say "note: the index file already has uncommitted changes; they are the baseline"
fi

if [ "$push" = 1 ] && [ "$dry" = 0 ]; then
    branch=$(git -C "$here" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ "$branch" = main ] || die "push requires branch 'main' (current: ${branch:-detached HEAD})"
    [ -n "$read_url" ] || die "no read URL: set INDEX_READ_URL or add an 'origin' remote"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/refresh-index.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

old="$work/index.old"
if [ -f "$index_file" ]; then
    cp "$index_file" "$old"
else
    : >"$old"
fi
new="$work/index.new"
: >"$new"

# `--only` keeps every row of the packages that are not being rebuilt, so a
# single release can refresh its own line without depending on the rest of the
# ecosystem being migrated.
if [ -n "$only" ]; then
    awk -v only="$only" '
        BEGIN { n = split(only, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
        NF >= 5 && !($1 in want)
    ' "$old" >"$new"
fi
skipped_tags="$work/skipped"
: >"$skipped_tags"

# semver-descending `v*` tags. `ls-remote` prints "<sha>\t<ref>", so take $2.
# No `sort -V`: BSD sort on macOS does not have it.
sort_tags() {
    awk '
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
            if (ref !~ /^v[0-9]/) next
            printf "%015.0f %s\n", key(ref), ref
        }
    ' | sort -rn | awk '{ print $2 }'
}

# ---------------------------------------------------------------------------
# Rebuild into $new. Nothing under the work tree is written until every newest
# tag validated and no published digest moved.
# ---------------------------------------------------------------------------
fatal=0
missing=0
while IFS=' ' read -r name url rest; do
    case "$name" in
        '' | '#'*) continue ;;
    esac
    [ -n "${url:-}" ] || continue
    if [ -n "$only" ]; then
        case " $only " in
            *" $name "*) ;;
            *) continue ;;
        esac
    fi

    if ! refs=$(git ls-remote --tags --refs "$url" 'v*' 2>"$work/ls.err"); then
        cat "$work/ls.err" >&2
        die "cannot list tags from $url"
    fi
    tags=$(printf '%s\n' "$refs" | sort_tags)
    if [ -z "$tags" ]; then
        say "skip     $name: no v* tag at $url"
        missing=$((missing + 1))
        continue
    fi
    newest=$(printf '%s\n' "$tags" | head -n 1)
    if [ "$all_tags" = 1 ]; then
        selected=$tags
    else
        selected=$newest
    fi

    # One clone per repository, then checkout each tag. `clone --branch <tag>`
    # warns on annotated tags, and `checkout tags/<tag>` peels both shapes.
    rm -rf "$work/$name"
    if ! git clone --quiet "$url" "$work/$name" 2>"$work/clone.err"; then
        cat "$work/clone.err" >&2
        die "clone failed for $name ($url)"
    fi

    pkg_pub=""
    for tag in $selected; do
        if ! git -C "$work/$name" -c advice.detachedHead=false checkout --quiet "tags/$tag" \
                2>"$work/checkout.err"; then
            cat "$work/checkout.err" >&2
            die "checkout of $name $tag failed"
        fi
        one="$work/one.index"
        : >"$one"
        if ! "$here/tools/gen-index.sh" "$one" "$work/$name" "$url" "$tag" >/dev/null \
                2>"$work/gen.err"; then
            if [ "$tag" = "$newest" ]; then
                printf 'refresh-index: %s %s: %s\n' "$name" "$tag" \
                    "$(head -n 1 "$work/gen.err")" >&2
                fatal=$((fatal + 1))
            else
                printf '%s %s: %s\n' "$name" "$tag" "$(head -n 1 "$work/gen.err")" \
                    >>"$skipped_tags"
            fi
            continue
        fi
        pub=$(awk '{ print $3 }' "$one")
        if [ -n "$pkg_pub" ] && [ "$pub" != "$pkg_pub" ]; then
            printf '%s %s: publisher %s differs from %s of the newest tag\n' \
                "$name" "$tag" "$pub" "$pkg_pub" >>"$skipped_tags"
            continue
        fi
        [ -n "$pkg_pub" ] || pkg_pub=$pub
        cat "$one" >>"$new"
        say "fetched  $name $tag"
    done
done <"$packages"

if [ "$missing" -gt 0 ]; then
    say "aborted: $missing package(s) have no v* tag; index left untouched"
    exit 1
fi
if [ "$fatal" -gt 0 ]; then
    say "aborted: $fatal newest tag(s) failed validation; index left untouched"
    exit 1
fi
if [ -s "$skipped_tags" ]; then
    say "note: older tags skipped (missing shared-store identity or drifted version):"
    sed 's/^/        /' "$skipped_tags"
fi

# ---------------------------------------------------------------------------
# Immutability: an indexed name+version may not change its digest.
# ---------------------------------------------------------------------------
rewritten=$(awk '
    FNR == NR {
        if (NF >= 6)      { k = $1 " " $2; t[k] = $5; h[k] = $6 }
        else if (NF >= 5) { k = $1 " " $2; t[k] = $4; h[k] = $5 }
        next
    }
    NF >= 6 {
        k = $1 " " $2
        if ((k in h) && h[k] != $6) printf "%s %s %s -> %s\n", $1, $2, h[k], $6
    }
' "$old" "$new")

if [ -n "$rewritten" ]; then
    printf 'refresh-index: an already indexed version changed its digest\n%s\n' "$rewritten" >&2
    if [ "$allow_rewrite" = 1 ]; then
        say "note: --allow-rewrite given; accepting the new digest"
    else
        die "tags are immutable: publish a new version instead (or pass --allow-rewrite on purpose)"
    fi
fi

# ---------------------------------------------------------------------------
# Report old -> new before touching the work tree.
# ---------------------------------------------------------------------------
normalize() {
    awk '
        NF >= 6 { print $1, $2, $3, $5, $6; next }
        NF >= 5 { print $1, $2, "-", $4, $5 }
    ' "$1"
}
normalize "$old" >"$work/old.norm"
normalize "$new" >"$work/new.norm"

report="$work/report"
{ cat "$work/old.norm"; printf '__NEW__\n'; cat "$work/new.norm"; } | awk '
    $0 == "__NEW__" { phase = 1; next }
    phase == 0 && NF >= 5 {
        k = $1 " " $2
        op[k] = $3; ot[k] = $4; oh[k] = $5; seen[k] = 1
        next
    }
    phase == 1 && NF >= 5 {
        k = $1 " " $2; nn[k] = 1
        if (!(k in seen)) {
            printf "added    %-10s %-7s %s %s\n", $1, $2, $4, $5
            added++
            next
        }
        if (ot[k] != $4 || oh[k] != $5 || op[k] != $3) {
            printf "changed  %-10s %s\n", $1, $2
            if (op[k] != $3) printf "         %-10s publisher %s -> %s\n", "", op[k], $3
            if (ot[k] != $4) printf "         %-10s tag %s -> %s\n", "", ot[k], $4
            if (oh[k] != $5) printf "         %-10s sha %s -> %s\n", "", oh[k], $5
            changed++
        } else {
            same++
        }
    }
    END {
        for (k in seen) {
            if (!(k in nn)) { split(k, p, " "); printf "removed  %s %s\n", p[1], p[2]; removed++ }
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
    say "[dry-run] would write $index_file ($lines lines); no files were modified"
    if [ "$changed" = 1 ]; then
        say "[dry-run] would commit the index file"
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
    cp "$new" "$index_file"
    if [ "$commit" = 0 ]; then
        say "index updated; run with --commit to commit it"
    fi
fi

if [ "$commit" = 1 ]; then
    if git -C "$here" diff --quiet -- "$index_rel"; then
        say "commit: index already matches HEAD; nothing to commit"
    else
        names=$(awk '/^changed  / { print $2 }' "$report" | sort -u | tr '\n' ' ' | sed 's/ *$//')
        msg="index: refresh"
        [ -z "$names" ] || msg="index: refresh $names"
        git -C "$here" add -- "$index_rel"
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

#!/usr/bin/env bash
#
# package.sh — one entry point for the whole package lifecycle.
#
# The two old scripts (`publish-package.sh`, `release-package.sh`) differed
# only in how the remote repository comes into existence; everything after the
# tag push was duplicated. This script keeps one copy of the shared path:
#
#   preflight -> push main + tag -> wait for the tag -> rebuild index ->
#   verify the row with `ct get` -> commit + push index -> sync repos.txt
#
# Usage:
#   tools/package.sh check [<name> ...]      read-only preflight for packages
#   tools/package.sh verify <name> <version> replay one index row with `ct get`
#   tools/package.sh publish <name>          create the repo if missing, push
#                                            main + the tag from repos.txt
#   tools/package.sh release <name> <tag>    push an existing local tag
#
# `publish` additionally needs RESTie and a token with repository creation
# rights; `release` only needs git. Both need the token for the HTTPS push and
# for pushing the refreshed index.
#
# Preflight (`check`, and the first step of the other two) runs the same gates
# the workspace uses:
#   * tag `v<version>` matches `ct.pkg`'s `version`;
#   * the package is a clean git work tree carrying that tag;
#   * `tools/package-check.sh` passes (identity, ns-root, absolute -I, version
#     and tag shape); it is pure shell and needs no compiler;
#   * `tools/check-layout.sh` passes (unit directory == namespace);
#   * `check` additionally runs `tools/check-char-host.sh` over the workspace.
#
# A compiler is only used after the index row is written, to replay it with
# `ct get`. That replay is mandatory: when no compiler is found, publish and
# release abort instead of pushing an unverified row (get-contract I10). The
# `check` path never invokes `ct`.
#
# Environment:
#   ORG         GitHub organisation (default ct-pkg)
#   STAGING     local checkout root (default ~/vscspace/ct-pkg)
#   MANIFEST    release manifest (default tools/repos.txt)
#   INDEX_DIR   index repository (default this repository)
#   CT_BIN      compiler/driver used to replay a fresh index row
#               (default `ct`, then `ct-ast`); a missing one aborts the
#               publish/release pipeline; `check` does not use it
#   GITHUB_TOKEN / GH_TOKEN   token used for the API and HTTPS pushes
#
# The script is idempotent and never force-pushes: an existing repository and
# an already pushed main are skipped, and a tag is pushed only when asked for.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
index_dir="${INDEX_DIR:-$here/..}"
ORG="${ORG:-ct-pkg}"
STAGING="${STAGING:-$HOME/vscspace/ct-pkg}"
MANIFEST="${MANIFEST:-$here/repos.txt}"
WORK="${TMPDIR:-/tmp}"
WORK="${WORK%/}"

fail() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok    %s\n' "$1"; }
info() { printf '  ..    %s\n' "$1"; }
warn() { printf '  warn  %s\n' "$1" >&2; }

usage() {
    cat <<'EOF'
usage: tools/package.sh <command> [args]

  check [<name> ...]      read-only preflight for packages (default: all)
  verify <name> <version> replay one existing index row with `ct get`;
                          exits non-zero when no compiler is found
  publish <name>          create the repo if missing, push main + the tag
                          from tools/repos.txt, then refresh and publish the
                          index
  release <name> <tag>    push an existing local tag, then refresh and
                          publish the index

Both publish and release end with the same pipeline:
  preflight -> push main + tag -> wait for the tag -> rebuild index ->
  verify the row with `ct get` -> commit + push index -> sync repos.txt

The replay is mandatory: without a compiler, publish and release abort
instead of pushing a row no consumer has installed (get-contract I10).

Environment:
  ORG         GitHub organisation (default ct-pkg)
  STAGING     local checkout root (default ~/vscspace/ct-pkg)
  MANIFEST    release manifest (default tools/repos.txt)
  INDEX_DIR   index repository (default this repository)
  CT_BIN      compiler/driver used to replay a fresh index row
              (default `ct`, then `ct-ast`); a missing one aborts
              publish/release; `check` does not use it
  GITHUB_TOKEN / GH_TOKEN   token for the API and HTTPS pushes

The script is idempotent and never force-pushes.
EOF
    exit "${1:-0}"
}

resolve_ct() {
    CT_BIN_RESOLVED="${CT_BIN:-}"
    if [ -z "$CT_BIN_RESOLVED" ]; then
        if command -v ct >/dev/null 2>&1; then
            CT_BIN_RESOLVED=ct
        elif command -v ct-ast >/dev/null 2>&1; then
            CT_BIN_RESOLVED=ct-ast
        fi
    fi
}

# ---------------------------------------------------------------------------
# Token and GitHub API
# ---------------------------------------------------------------------------
if [ -z "${GITHUB_TOKEN:-}" ] && [ -n "${GH_TOKEN:-}" ]; then
    GITHUB_TOKEN="$GH_TOKEN"
    export GITHUB_TOKEN
    info "GITHUB_TOKEN unset; using GH_TOKEN"
fi

api_cfg=""
api() {
    [ -n "$api_cfg" ] || fail "internal: api() before api_init"
    restie --config "$api_cfg" "$@"
}
api_init() {
    command -v restie >/dev/null 2>&1 \
        || fail "RESTie is not on PATH; it is required for repository creation"
    [ -n "${GITHUB_TOKEN:-}" ] \
        || fail "set GITHUB_TOKEN (or GH_TOKEN) first: export GITHUB_TOKEN=github_pat_xxx"
    api_cfg="$WORK/restie-github.yaml"
    cat > "$api_cfg" <<'YAML'
site:
  name: GitHub
  base_url: https://api.github.com
  auth:
    type: bearer_token
    token_env: GITHUB_TOKEN
YAML
}

# Push through HTTPS with the token supplied per command; it is never stored in
# .git/config. Without a token the user's normal git auth is used.
push_git() {
    local dir="$1"; shift
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        GIT_TERMINAL_PROMPT=0 git -C "$dir" \
            -c credential.helper= \
            -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$GITHUB_TOKEN"; }; f' \
            "$@"
    else
        GIT_TERMINAL_PROMPT=0 git -C "$dir" "$@"
    fi
}

# Push `main` with the same guards as refresh-index.sh --push: refuse a
# non-fast-forward update before pushing, never force, and read the remote tip
# back afterwards. `label` names the pushed artifact in diagnostics.
guard_push() {
    local dir="$1" label="$2" url remote_sha head after
    url=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
    remote_sha=$(git -C "$dir" ls-remote origin refs/heads/main 2>/dev/null \
        | awk '{ print $1 }')
    if [ -n "$remote_sha" ]; then
        git -C "$dir" fetch --quiet origin main \
            || fail "cannot fetch main from ${url:-origin} before pushing $label"
        remote_sha=$(git -C "$dir" ls-remote origin refs/heads/main | awk '{ print $1 }')
        head=$(git -C "$dir" rev-parse HEAD)
        if [ -n "$remote_sha" ] && ! git -C "$dir" merge-base --is-ancestor "$remote_sha" HEAD; then
            fail "remote main ($remote_sha) at ${url:-origin} is not an ancestor of HEAD ($head); refusing a non-fast-forward $label push"
        fi
    fi
    head=$(git -C "$dir" rev-parse HEAD)
    push_git "$dir" push origin main || fail "pushing $label failed"
    after=$(git -C "$dir" ls-remote origin refs/heads/main | awk '{ print $1 }')
    [ "$after" = "$head" ] \
        || fail "verification failed for $label: remote main is ${after:-<missing>}, local HEAD is $head"
}

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------
row_name=""; row_tag=""; row_content=""; row_desc=""
manifest_row() {
    local want="$1" n t c d
    row_name=""; row_tag=""; row_content=""; row_desc=""
    [ -f "$MANIFEST" ] || return 1
    while IFS='|' read -r n t c d; do
        case "$n" in "" | \#*) continue ;; esac
        if [ "$n" = "$want" ]; then
            row_name="$n"; row_tag="$t"; row_content="$c"; row_desc="$d"
            return 0
        fi
    done <"$MANIFEST"
    return 1
}

manifest_names() {
    local n t c d
    [ -f "$MANIFEST" ] || return 0
    while IFS='|' read -r n t c d; do
        case "$n" in "" | \#*) continue ;; esac
        printf '%s\n' "$n"
    done <"$MANIFEST"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
pkg_dir=""; pkg_tag=""
preflight() {
    local name="$1" tag="$2" dir="$STAGING/$1" ver
    pkg_dir="$dir"; pkg_tag="$tag"

    [ -d "$dir/.git" ] || fail "$dir is not a git repository; clone or create it first"
    [ -n "$tag" ] || fail "$name has no tag (the manifest row says '-')"

    case "$tag" in
        v[0-9]*) ;;
        *) fail "the tag must look like v1.0.1 (got '$tag')" ;;
    esac

    git -C "$dir" tag -l "$tag" | grep -q . \
        || fail "tag $tag is missing in $dir; create it with: git -C $dir tag -a $tag -m '...'"

    [ -z "$(git -C "$dir" status --porcelain)" ] \
        || fail "$dir has uncommitted changes; commit or stash them first"

    [ -f "$dir/ct.pkg" ] || fail "$dir has no ct.pkg"
    ver=$(awk -F= '
        {
            key = $1
            gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key != "version") next
            v = $0; sub(/^[^=]*=/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
            print v; exit
        }' "$dir/ct.pkg")
    [ "$ver" = "${tag#v}" ] \
        || fail "ct.pkg says version = '$ver' but the tag is '$tag'"

    if [ -x "$here/package-check.sh" ]; then
        "$here/package-check.sh" "$dir" >"$WORK/.pkgcheck.out" 2>&1 \
            || { sed 's/^/        /' "$WORK/.pkgcheck.out" >&2; fail "package-check failed for $name"; }
        ok "$name: package-check"
    else
        fail "$here/package-check.sh is missing; the release lint cannot run"
    fi

    if [ -x "$here/check-layout.sh" ]; then
        "$here/check-layout.sh" "$dir" >"$WORK/.layout.out" 2>&1 \
            || { sed 's/^/        /' "$WORK/.layout.out" >&2; fail "check-layout failed for $name"; }
        ok "$name: check-layout"
    fi

    ok "$name $tag (manifest, clean tree, tag/version, identity)"
}

workspace_gates() {
    if [ -x "$here/check-char-host.sh" ]; then
        if CT_PKG_ROOT="$STAGING" "$here/check-char-host.sh"; then
            ok "check-char-host"
        else
            fail "check-char-host failed (see above)"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Index pipeline
# ---------------------------------------------------------------------------
rebuild_index() {
    local name="$1"
    [ -d "$index_dir/.git" ] || fail "$index_dir is not a git repository (set INDEX_DIR)"
    info "rebuilding the '$name' rows in $index_dir"
    if ! ( cd "$index_dir" && ./tools/refresh-index.sh --only "$name" ); then
        fail "refresh-index.sh failed; is the new tag visible at github.com/$ORG?"
    fi
    ok "index rebuilt"
}

verify_row() {
    local name="$1" version="$2"
    resolve_ct
    if [ -z "$CT_BIN_RESOLVED" ]; then
        fail "ct not found: the consumer replay of '$name' is required before the index is pushed (get-contract I10); install ct or point CT_BIN at it"
    fi
    info "replaying $name@$version through $CT_BIN_RESOLVED get"
    if ! ( cd "$index_dir" && CT_BIN="$CT_BIN_RESOLVED" \
            ./tools/verify-index.sh --name "$name" --version "$version" ); then
        fail "the freshly written index row does not install; the push to the index was not attempted"
    fi
}

publish_index() {
    local msg="$1" dirty
    dirty=$(git -C "$index_dir" status --porcelain -- index)
    if [ -z "$dirty" ]; then
        info "the index already names this release; nothing to commit"
    else
        git -C "$index_dir" add index
        git -C "$index_dir" commit -q -m "index: $msg" || fail "committing the index failed"
        guard_push "$index_dir" index
        ok "index committed and pushed"
    fi
}

sync_manifest() {
    local name="$1" tag="$2" rel
    if [ -x "$here/sync-repos-tags.sh" ]; then
        "$here/sync-repos-tags.sh" >/dev/null || true
    fi
    case "$MANIFEST" in
        "$index_dir"/*) rel="${MANIFEST#"$index_dir"/}" ;;
        *) return 0 ;;
    esac
    if git -C "$index_dir" diff --quiet -- "$rel"; then
        return 0
    fi
    git -C "$index_dir" add -- "$rel"
    git -C "$index_dir" commit -q -m "repos.txt: $name -> $tag" \
        || fail "committing $rel failed"
    push_git "$index_dir" push origin main || fail "pushing $rel failed"
    ok "$rel: $name -> $tag"
}

wait_for_tag() {
    local name="$1" tag="$2" url="https://github.com/$ORG/$name.git" i
    for i in 1 2 3 4 5 6; do
        if git ls-remote --tags "$url" "refs/tags/$tag" 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 2
    done
    fail "tag $tag is not visible at $url after pushing; the index cannot resolve it yet"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_check() {
    local failed=0 name list tag
    if [ $# -gt 0 ]; then
        list=$(printf '%s\n' "$@")
    else
        list=$(manifest_names)
    fi
    [ -n "$list" ] || fail "no package rows in $MANIFEST"

    echo "== preflight =="
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        manifest_row "$name" || fail "'$name' is not a row in $MANIFEST"
        tag="$row_tag"
        echo
        echo "--- $name ---"
        if ! ( preflight "$name" "$tag" ); then
            failed=$((failed + 1))
        fi
    done <<<"$list"

    echo
    echo "== workspace gates =="
    workspace_gates

    echo
    if [ "$failed" -ne 0 ]; then
        fail "$failed package(s) failed the preflight"
    fi
    ok "every package passed the preflight"
}

cmd_release() {
    local name="$1" tag="$2"

    echo "== preflight =="
    preflight "$name" "$tag"

    echo
    echo "== push $name =="
    push_git "$STAGING/$name" push origin main || fail "pushing $name/main failed"
    push_git "$STAGING/$name" push origin "$tag" || fail "pushing $name $tag failed"
    ok "$name $tag pushed"
    wait_for_tag "$name" "$tag"

    echo
    echo "== rebuild $ORG/index =="
    rebuild_index "$name"
    verify_row "$name" "${tag#v}"

    echo
    echo "== publish the index =="
    publish_index "$name $tag"

    echo
    echo "== tools/repos.txt =="
    sync_manifest "$name" "$tag"

    echo
    echo "== done =="
    grep "^$name " "$index_dir/index" || true
}

cmd_publish() {
    local name="$1" tag content desc err url

    echo "== preflight =="
    manifest_row "$name" || fail "'$name' is not a row in $MANIFEST"
    tag="$row_tag"; content="$row_content"; desc="$row_desc"
    [ "$tag" != "-" ] || fail "$name has no tag in $MANIFEST; publish needs a release tag"
    api_init
    preflight "$name" "$tag"

    echo
    echo "== repository $ORG/$name =="
    err="$WORK/.restie-$name.err"
    if api GET "/repos/$ORG/$name" >/dev/null 2>"$err"; then
        info "$name already exists"
    elif grep -q '404' "$err"; then
        local body
        body=$(printf '{"name":"%s","description":"%s","private":false,"auto_init":false,"has_issues":false,"has_projects":false,"has_wiki":false}' \
            "$name" "$desc")
        api POST "/orgs/$ORG/repos" "$body" >/dev/null 2>"$err" \
            || { sed 's/^/        /' "$err" >&2; fail "could not create $ORG/$name"; }
        ok "created $ORG/$name"
    else
        sed 's/^/        /' "$err" >&2
        fail "the API rejected the existence check for $ORG/$name"
    fi

    url="https://github.com/$ORG/$name.git"
    if git -C "$STAGING/$name" remote get-url origin >/dev/null 2>&1; then
        git -C "$STAGING/$name" remote set-url origin "$url"
    else
        git -C "$STAGING/$name" remote add origin "$url"
    fi
    if git -C "$STAGING/$name" ls-remote --heads origin main 2>/dev/null | grep -q .; then
        info "$name: origin already has main, skipping the branch push"
    else
        err="$WORK/.push-$name.err"
        if ! push_git "$STAGING/$name" push -u origin main 2>"$err"; then
            if grep -q 'workflow.*scope' "$err"; then
                printf '\nERROR: the token lacks the `workflow` scope.\n' >&2
                printf '       GitHub refused to push a file under .github/workflows/ (%s).\n' "$name" >&2
                printf '       Add the `workflow` scope to the classic PAT, export it again, then rerun.\n' >&2
                exit 1
            fi
            sed 's/^/        /' "$err" >&2
            fail "push of $name/main failed (delete a README-created repo and rerun)"
        fi
        ok "$name: main pushed"
    fi
    push_git "$STAGING/$name" push origin "$tag" || fail "push of $name $tag failed"
    ok "$name: $tag pushed"

    if api GET "/repos/$ORG/$name/contents/$content" >/dev/null 2>"$err"; then
        ok "$name/$content is on github.com"
    else
        sed 's/^/        /' "$err" >&2
        fail "$name/$content is not readable on github.com (did the push land?)"
    fi
    wait_for_tag "$name" "$tag"

    echo
    echo "== rebuild $ORG/index =="
    rebuild_index "$name"
    verify_row "$name" "${tag#v}"

    echo
    echo "== publish the index =="
    publish_index "$name $tag"

    echo
    echo "== tools/repos.txt =="
    sync_manifest "$name" "$tag"

    echo
    echo "== done =="
    grep "^$name " "$index_dir/index" || true
}

cmd_verify() {
    local name="$1" version="$2"
    verify_row "$name" "$version"
    ok "$name $version replayed through $CT_BIN_RESOLVED"
}

# ---------------------------------------------------------------------------
main() {
    [ $# -ge 1 ] || usage 2
    local cmd="$1"; shift
    case "$cmd" in
        check)
            cmd_check "$@" ;;
        verify)
            [ $# -eq 2 ] || usage 2
            cmd_verify "$1" "$2" ;;
        release)
            [ $# -eq 2 ] || usage 2
            cmd_release "$1" "$2" ;;
        publish)
            [ $# -eq 1 ] || usage 2
            cmd_publish "$1" ;;
        -h | --help | help)
            usage 0 ;;
        *)
            printf 'package: unknown command %s\n\n' "$cmd" >&2
            usage 2 ;;
    esac
}
main "$@"

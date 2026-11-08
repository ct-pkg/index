#!/usr/bin/env bash
#
# publish-package.sh — create (if missing) and push a ct-pkg repository through
# the GitHub REST API, then read the landing commit back.
#
# Package rows live in tools/repos.txt, one per line:
#
#   name|tag|content|description
#
#   name         repository name, which is also the package name
#   tag          the tag to push, or `-` for none (the index repo has none)
#   content      a file to read back after the push (`ct.pkg`, or `index`)
#   description  the repository description shown on GitHub
#
# Usage:
#   tools/publish-package.sh              # every row in repos.txt
#   tools/publish-package.sh std          # just one package
#
# Adding a package later:
#   1. create/clone its repository under ~/vscspace/ct-pkg/<name>
#   2. write ct.pkg + sources, commit, and tag it (git tag v1.0.1)
#   3. append one row to tools/repos.txt
#   4. tools/publish-package.sh <name>
#
# Requirements:
#   - RESTie, already installed in the user environment
#   - GITHUB_TOKEN in the environment, with permission to create repositories
#     in the ct-pkg organization. Fine-grained PAT: Organization
#     "Administration: Read and write" plus "Contents: Read and write".
#     Classic PAT: the `repo` and `workflow` scopes (the index repo carries
#     .github/workflows/index.yml, so `workflow` is required too).
#     GH_TOKEN is accepted as a fallback.
#   - git authenticated, or the same token is used for the HTTPS push (the
#     script injects it per-command and never writes it into .git/config).
#
# Env overrides: ORG (default ct-pkg), STAGING (default ~/vscspace/ct-pkg),
#                MANIFEST (default tools/repos.txt).
#
# The script is idempotent: an existing repository is skipped, an already
# pushed main branch is skipped, and a tag is pushed only when it is asked for.
# It never deletes or force-pushes anything.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
ORG="${ORG:-ct-pkg}"
STAGING="${STAGING:-$HOME/vscspace/ct-pkg}"
MANIFEST="${MANIFEST:-$here/repos.txt}"
WORK="${TMPDIR:-/tmp}"
WORK="${WORK%/}"

fail() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok    %s\n' "$1"; }
info() { printf '  ..    %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------------
echo "== preflight =="

command -v git >/dev/null 2>&1 || fail "git is not on PATH"
[ -f "$MANIFEST" ] || fail "no manifest at $MANIFEST"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    if [ -n "${GH_TOKEN:-}" ]; then
        GITHUB_TOKEN="$GH_TOKEN"
        export GITHUB_TOKEN
        info "GITHUB_TOKEN unset; using GH_TOKEN"
    else
        fail "set GITHUB_TOKEN (or GH_TOKEN) first: export GITHUB_TOKEN=github_pat_xxx"
    fi
fi

# A minimal site config: no OpenAPI spec download, just base URL + bearer auth.
CFG="$WORK/restie-github.yaml"
cat > "$CFG" <<'YAML'
site:
  name: GitHub
  base_url: https://api.github.com
  auth:
    type: bearer_token
    token_env: GITHUB_TOKEN
YAML
api() { restie --config "$CFG" "$@"; }

# ---------------------------------------------------------------------------
# Select the rows to publish
# ---------------------------------------------------------------------------
rows=()
while IFS='|' read -r name tag content desc; do
    case "$name" in
        ""|\#*) continue ;;
    esac
    if [ -n "${1:-}" ] && [ "$name" != "$1" ]; then
        continue
    fi
    rows+=("$name|$tag|$content|$desc")
done < "$MANIFEST"

if [ "${#rows[@]}" -eq 0 ]; then
    if [ -n "${1:-}" ]; then
        fail "'$1' is not a row in $MANIFEST"
    fi
    fail "no package rows in $MANIFEST"
fi

for row in "${rows[@]}"; do
    IFS='|' read -r name _tag _content _desc <<< "$row"
    [ -d "$STAGING/$name/.git" ] \
        || fail "$STAGING/$name is not a git repository; clone or create it first"
done
ok "manifest: ${#rows[@]} package row(s)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create the repository when the API says it does not exist yet.
ensure_repo() {
    local name="$1" desc="$2" err="$WORK/.restie-$1.err" body
    if api GET "/repos/$ORG/$name" >/dev/null 2>"$err"; then
        info "$name already exists"
        return
    fi
    if ! grep -q '404' "$err"; then
        printf '    %s\n' "$(cat "$err")"
        fail "the API rejected the existence check for $ORG/$name"
    fi
    body=$(printf '{"name":"%s","description":"%s","private":false,"auto_init":false,"has_issues":false,"has_projects":false,"has_wiki":false}' \
        "$name" "$desc")
    if api POST "/orgs/$ORG/repos" "$body" >/dev/null 2>"$err"; then
        ok "created $ORG/$name"
    else
        printf '    %s\n' "$(cat "$err")"
        fail "could not create $ORG/$name (see the API error above)"
    fi
}

# Push through HTTPS with the token supplied per command; it is never stored
# in .git/config. Without a token we fall back to the user's normal git auth.
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

push_repo() {
    local name="$1" tag="$2" dir="$STAGING/$1"
    local url="https://github.com/$ORG/$name.git" err

    if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
        git -C "$dir" remote set-url origin "$url"
    else
        git -C "$dir" remote add origin "$url"
    fi

    if git -C "$dir" ls-remote --heads origin main 2>/dev/null | grep -q .; then
        info "$name: origin already has main, skipping the branch push"
    else
        err="$WORK/.push-$name.err"
        if ! push_git "$dir" push -u origin main 2>"$err"; then
            if grep -q 'workflow.*scope' "$err"; then
                printf '\nERROR: the token lacks the `workflow` scope.\n' >&2
                printf '       GitHub refused to push a file under .github/workflows/ (%s).\n' "$name" >&2
                printf '       Add the `workflow` scope to the classic PAT (the token string changes),\n' >&2
                printf '       export it again, then rerun this script.\n' >&2
                exit 1
            fi
            printf '    %s\n' "$(cat "$err")" >&2
            fail "push of $name/main failed. If the repository was created with a README, delete it and recreate it empty, then rerun."
        fi
        ok "$name: main pushed"
    fi

    if [ "$tag" = "-" ]; then
        return
    fi
    if ! git -C "$dir" tag -l "$tag" | grep -q .; then
        fail "tag $tag is missing in $dir; create it with: git -C $dir tag $tag"
    fi
    if ! push_git "$dir" push origin "$tag"; then
        fail "push of $name $tag failed"
    fi
    ok "$name: $tag pushed"
}

# Confirm the pushed tree is actually readable through the API.
readback() {
    local name="$1" path="$2" err="$WORK/.restie-$1-read.err"
    if api GET "/repos/$ORG/$name/contents/$path" >/dev/null 2>"$err"; then
        ok "$name/$path is on github.com"
    else
        printf '    %s\n' "$(cat "$err")"
        fail "$name/$path is not readable on github.com (did the push land?)"
    fi
}

# ---------------------------------------------------------------------------
# Publish
# ---------------------------------------------------------------------------
for row in "${rows[@]}"; do
    IFS='|' read -r name tag content desc <<< "$row"
    echo
    echo "--- $name ---"
    ensure_repo "$name" "$desc"
    push_repo "$name" "$tag"
    readback "$name" "$content"
done

echo
echo "== done =="
echo "repositories: https://github.com/$ORG"

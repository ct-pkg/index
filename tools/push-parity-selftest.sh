#!/usr/bin/env bash
#
# push-parity-selftest.sh — exercise package.sh's index push guards.
#
# `refresh-index.sh --push` refuses non-fast-forward pushes, never forces and
# reads the remote tip back after pushing. `package.sh` is the main release
# path, so it must do the same. This selftest drives the real publish_index()
# and sync_manifest() functions against local bare repositories.
#
# The functions live in package.sh, which runs main() at the bottom. To call
# them without a real release, copy the file without that last line and source
# the copy; the copy's `here` is reset to the temp root so sync_manifest does
# not touch the real repository.
#
# Usage: bash tools/push-parity-selftest.sh
# Exit status: 0 when all four cases match, 1 otherwise.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root=$(mktemp -d "${TMPDIR:-/tmp}/push-parity.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

# Do not leak credentials into file:// pushes.
unset GITHUB_TOKEN GH_TOKEN

sed '$d' "$here/package.sh" >"$root/package-lib.sh"
# shellcheck disable=SC1091
. "$root/package-lib.sh"
# package.sh computed `here` from $0 (this selftest). Point it at the temp
# root so its optional sync-repos-tags.sh call is skipped.
here="$root"

passed=0
failed=0

pass() { passed=$((passed + 1)); printf '  -> PASS  %s\n' "$1"; }
bad()  { failed=$((failed + 1)); printf '  -> FAIL  %s\n' "$1"; }

# new_remote <case> -> sets case_dir, remote, work.
new_remote() {
    local name="$1"
    case_dir="$root/$name"
    remote="$case_dir/remote.git"
    work="$case_dir/work"
    mkdir -p "$case_dir"
    git init -q --bare "$remote"
    git -C "$remote" symbolic-ref HEAD refs/heads/main

    git init -q "$case_dir/seed"
    git -C "$case_dir/seed" symbolic-ref HEAD refs/heads/main
    git -C "$case_dir/seed" config user.name selftest
    git -C "$case_dir/seed" config user.email selftest@example.com
    printf 'std 0.1.0 ct https://example.invalid/std v0.1.0 sha256:%064d\n' 0 \
        >"$case_dir/seed/index"
    mkdir -p "$case_dir/seed/tools"
    printf '# manifest\nstd|v0.1.0|ct.pkg|demo\n' >"$case_dir/seed/tools/repos.txt"
    git -C "$case_dir/seed" add -A
    git -C "$case_dir/seed" commit -qm initial
    git -C "$case_dir/seed" remote add origin "$remote"
    git -C "$case_dir/seed" push -q origin main

    git clone -q "$remote" "$work"
    git -C "$work" config user.name selftest
    git -C "$work" config user.email selftest@example.com
}

# advance_remote <case> <path> <text> — push a new commit from a second clone.
advance_remote() {
    local name="$1" path="$2" text="$3" other="$root/$1/other"
    git clone -q "$root/$1/remote.git" "$other"
    git -C "$other" config user.name other
    git -C "$other" config user.email other@example.com
    printf '%s\n' "$text" >"$other/$path"
    git -C "$other" add -A
    git -C "$other" commit -qm ahead
    git -C "$other" push -q origin main
}

remote_tip() {
    git ls-remote "$1" refs/heads/main | awk '{print $1}'
}

run_publish() {
    local dir="$1"
    ( index_dir="$dir"; MANIFEST="$dir/tools/repos.txt"; here="$root"; \
      publish_index selftest ) 2>&1
}

run_sync() {
    local dir="$1"
    ( index_dir="$dir"; MANIFEST="$dir/tools/repos.txt"; here="$root"; \
      sync_manifest std v0.2.0 ) 2>&1
}

# ---------------------------------------------------------------------------
# publish_index: remote ahead must be refused before the push.
# ---------------------------------------------------------------------------
printf '== publish_index: remote ahead ==\n'
new_remote publish-ahead
advance_remote publish-ahead index 'remote-only'
before=$(remote_tip "$remote")
printf 'local-only\n' >"$work/index"
out=$(run_publish "$work"); rc=$?
printf '  rc=%d\n' "$rc"
printf '%s\n' "$out" | sed 's/^/  | /'
after=$(remote_tip "$remote")
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'not an ancestor' \
        && [ "$before" = "$after" ]; then
    pass "remote-ahead push is refused and the remote tip is unchanged"
else
    bad "remote-ahead push must be refused with 'not an ancestor' and leave the remote tip"
fi

# ---------------------------------------------------------------------------
# publish_index: remote consistent must push and read back.
# ---------------------------------------------------------------------------
printf '== publish_index: remote consistent ==\n'
new_remote publish-ok
printf 'local-only\n' >"$work/index"
out=$(run_publish "$work"); rc=$?
printf '  rc=%d\n' "$rc"
printf '%s\n' "$out" | sed 's/^/  | /'
head=$(git -C "$work" rev-parse HEAD)
after=$(remote_tip "$remote")
if [ "$rc" -eq 0 ] && [ "$after" = "$head" ]; then
    pass "consistent push succeeds and the remote tip equals local HEAD"
else
    bad "consistent push must succeed and read the remote tip back"
fi

# ---------------------------------------------------------------------------
# sync_manifest: remote ahead must be refused before the push.
# ---------------------------------------------------------------------------
printf '== sync_manifest: remote ahead ==\n'
new_remote sync-ahead
advance_remote sync-ahead tools/repos.txt 'remote-only'
before=$(remote_tip "$remote")
printf 'local-only\n' >"$work/tools/repos.txt"
out=$(run_sync "$work"); rc=$?
printf '  rc=%d\n' "$rc"
printf '%s\n' "$out" | sed 's/^/  | /'
after=$(remote_tip "$remote")
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'not an ancestor' \
        && [ "$before" = "$after" ]; then
    pass "remote-ahead manifest push is refused and the remote tip is unchanged"
else
    bad "remote-ahead manifest push must be refused with 'not an ancestor'"
fi

# ---------------------------------------------------------------------------
# sync_manifest: remote consistent must push and read back.
# ---------------------------------------------------------------------------
printf '== sync_manifest: remote consistent ==\n'
new_remote sync-ok
printf 'local-only\n' >"$work/tools/repos.txt"
out=$(run_sync "$work"); rc=$?
printf '  rc=%d\n' "$rc"
printf '%s\n' "$out" | sed 's/^/  | /'
head=$(git -C "$work" rev-parse HEAD)
after=$(remote_tip "$remote")
if [ "$rc" -eq 0 ] && [ "$after" = "$head" ]; then
    pass "consistent manifest push succeeds and the remote tip equals local HEAD"
else
    bad "consistent manifest push must succeed and read the remote tip back"
fi

printf '\nsummary: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]

#!/usr/bin/env bash
#
# gate-selftest.sh — exercise check-layout.sh and check-char-host.sh.
#
# Every fixture is created in a temporary directory, so the repository stays
# clean and no package checkout is needed. The cases cover the zero-input
# rule (an empty workspace root must fail, not print `ok: 0`) and keep the
# existing positive/negative behaviour pinned.
#
# Usage: bash tools/gate-selftest.sh
# Exit status: 0 when every case matches its expectation, 1 otherwise.

set -u

here="$(cd "$(dirname "$0")" && pwd)"
layout="$here/check-layout.sh"
charhost="$here/check-char-host.sh"
root=$(mktemp -d "${TMPDIR:-/tmp}/gate-selftest.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

passed=0
failed=0

# run_case <label> <expected-rc> <script> <needle> [<CT_PKG_ROOT>]
# An empty <needle> means "do not check the output".
run_case() {
    local label="$1" expected="$2" script="$3" needle="$4" pkgroot="${5:-}"
    local out rc
    out=$(CT_PKG_ROOT="$pkgroot" bash "$script" 2>&1)
    rc=$?
    printf '$ CT_PKG_ROOT=%s bash tools/%s\n' "${pkgroot#"$root"/}" "$(basename "$script")"
    if [ "$rc" -ne "$expected" ]; then
        printf '  -> rc=%d (expected %d) FAIL  %s\n' "$rc" "$expected" "$label"
        failed=$((failed + 1))
        printf '%s\n' "$out" | sed 's/^/     | /'
        return
    fi
    if [ -n "$needle" ] && ! printf '%s\n' "$out" | grep -q -- "$needle"; then
        printf '  -> rc=%d PASS but output lacks %s FAIL  %s\n' "$rc" "'$needle'" "$label"
        failed=$((failed + 1))
        printf '%s\n' "$out" | sed 's/^/     | /'
        return
    fi
    printf '  -> rc=%d PASS  %s\n' "$rc" "$label"
    passed=$((passed + 1))
}

mkpkg() {
    local ws="$1" name="$2"
    mkdir -p "$ws/$name"
    printf 'name = %s\npublisher = ct\nversion = 0.1.0\nns-root = .\n' "$name" \
        >"$ws/$name/ct.pkg"
}

# ---------------------------------------------------------------------------
# Zero input: an empty or missing workspace root must fail.
# ---------------------------------------------------------------------------
empty="$root/empty"
mkdir -p "$empty"
run_case "layout fails on an empty workspace" 1 "$layout" "no packages found" "$empty"
run_case "char-host fails on an empty workspace" 1 "$charhost" "no packages found" "$empty"

# ---------------------------------------------------------------------------
# Explicit arguments must name a real package.
# ---------------------------------------------------------------------------
nojs="$root/no-manifest"
mkdir -p "$nojs/plain"
out=$(bash "$layout" "$nojs/plain" 2>&1)
rc=$?
printf '$ bash tools/check-layout.sh %s\n' "${nojs#"$root"/}/plain"
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "has no ct.pkg"; then
    printf '  -> rc=1 PASS  layout rejects a directory without ct.pkg\n'
    passed=$((passed + 1))
else
    printf '  -> rc=%d FAIL  layout rejects a directory without ct.pkg\n' "$rc"
    printf '%s\n' "$out" | sed 's/^/     | /'
    failed=$((failed + 1))
fi

# ---------------------------------------------------------------------------
# Layout: namespace must match the unit directory.
# ---------------------------------------------------------------------------
ws_ok="$root/ws-ok"
mkpkg "$ws_ok" hello
mkdir -p "$ws_ok/hello/a/b"
printf 'namespace a::b;\npub fn hi() {}\n' >"$ws_ok/hello/a/b/x.ct"
run_case "layout accepts a matching namespace" 0 "$layout" "ok: 1 namespaced units" "$ws_ok"

ws_bad="$root/ws-bad"
mkpkg "$ws_bad" hello
mkdir -p "$ws_bad/hello/a/c"
printf 'namespace a::b;\npub fn hi() {}\n' >"$ws_bad/hello/a/c/x.ct"
run_case "layout rejects a mismatched namespace" 1 "$layout" "expects directory" "$ws_bad"

# ---------------------------------------------------------------------------
# Char-host: no mapped method is fine; duplicates and qualified hosts are not.
# ---------------------------------------------------------------------------
ws_none="$root/ws-none"
mkpkg "$ws_none" hello
run_case "char-host accepts a package without mapped methods" 0 "$charhost" \
    "ok: 0 methods on 0 hosts" "$ws_none"

ws_dup="$root/ws-dup"
mkpkg "$ws_dup" first
mkpkg "$ws_dup" second
printf 'map trait util for type char {\n    len(\n}\n' >"$ws_dup/first/bind.m.ct"
printf 'map trait util for type char {\n    len(\n}\n' >"$ws_dup/second/bind.m.ct"
run_case "char-host rejects a duplicate method on one host" 1 "$charhost" \
    "duplicate method name" "$ws_dup"

ws_cv="$root/ws-cv"
mkpkg "$ws_cv" hello
printf 'map trait util for type const char {\n    foo(\n}\n' >"$ws_cv/hello/bind.m.ct"
run_case "char-host rejects a const-qualified host" 1 "$charhost" \
    "const/volatile host" "$ws_cv"

# ---------------------------------------------------------------------------
printf '\nsummary: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]

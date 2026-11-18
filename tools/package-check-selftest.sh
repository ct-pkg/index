#!/usr/bin/env bash
#
# package-check-selftest.sh — exercise tools/package-check.sh.
#
# Every fixture is created in a temporary directory, so the repository stays
# clean. Each case prints the command it ran and the exit status it observed.
#
# Usage: bash tools/package-check-selftest.sh
# Exit status: 0 when every case matches its expectation, 1 otherwise.

set -u

here="$(cd "$(dirname "$0")" && pwd)"
check="$here/package-check.sh"
root=$(mktemp -d "${TMPDIR:-/tmp}/package-check-selftest.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

passed=0
failed=0

run_case() {
    local label="$1" expected="$2" dir="$3"
    shift 3
    local out rc
    out=$("$check" "$@" "$dir" 2>&1)
    rc=$?
    printf '$ bash tools/package-check.sh %s%s\n' "${*:+$* }" "${dir#"$root"/}"
    if [ "$rc" -eq "$expected" ]; then
        printf '  -> rc=%d (expected %d) PASS  %s\n' "$rc" "$expected" "$label"
        passed=$((passed + 1))
    else
        printf '  -> rc=%d (expected %d) FAIL  %s\n' "$rc" "$expected" "$label"
        failed=$((failed + 1))
    fi
    printf '%s\n' "$out" | sed 's/^/     | /'
}

pkg() {
    local d="$root/$1"
    mkdir -p "$d"
    printf '%s\n' "$d"
}

# ---------------------------------------------------------------------------
# Positive fixtures.
# ---------------------------------------------------------------------------
valid=$(pkg valid)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\n' >"$valid/ct.pkg"
printf 'pub fn hi() {}\n' >"$valid/Hi.h.ct"

rel_inc=$(pkg rel-inc)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\n' >"$rel_inc/ct.pkg"
printf 'cflags = -I .\n' >"$rel_inc/flags.ct"

strict_ok=$(pkg strict-ok)
mkdir -p "$strict_ok/acme"
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\ndep = std@^0.3.0\nrequires = ct >= 0.54.0\nc-boundary = strict\n' \
    >"$strict_ok/ct.pkg"
printf 'namespace acme;\npub fn hi() {}\n' >"$strict_ok/acme/Thing.h.ct"

# A git checkout tagged exactly at the manifest version.
tagged=$(pkg tagged)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\n' >"$tagged/ct.pkg"
printf 'pub fn hi() {}\n' >"$tagged/Hi.h.ct"
git -C "$tagged" init -q -b main
git -C "$tagged" add -A
git -C "$tagged" -c user.email=t@example.com -c user.name=t commit -qm init
git -C "$tagged" tag v0.1.0

# ---------------------------------------------------------------------------
# Negative fixtures: identity.
# ---------------------------------------------------------------------------
no_name=$(pkg no-name)
printf 'publisher = acme\nversion = 0.1.0\nns-root = .\n' >"$no_name/ct.pkg"

no_pub=$(pkg no-publisher)
printf 'name = hello\nversion = 0.1.0\nns-root = .\n' >"$no_pub/ct.pkg"

no_ver=$(pkg no-version)
printf 'name = hello\npublisher = acme\nns-root = .\n' >"$no_ver/ct.pkg"

no_ns=$(pkg no-ns-root)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\n' >"$no_ns/ct.pkg"

pub_local=$(pkg publisher-local)
printf 'name = hello\npublisher = local\nversion = 0.1.0\nns-root = .\n' >"$pub_local/ct.pkg"

bad_name=$(pkg bad-name)
printf 'name = bad/name\npublisher = acme\nversion = 0.1.0\nns-root = .\n' >"$bad_name/ct.pkg"

bad_ver=$(pkg bad-version)
printf 'name = hello\npublisher = acme\nversion = 0.1\nns-root = .\n' >"$bad_ver/ct.pkg"

# ---------------------------------------------------------------------------
# Negative fixtures: ns-root and absolute -I.
# ---------------------------------------------------------------------------
ns_abs=$(pkg ns-absolute)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = /tmp\n' >"$ns_abs/ct.pkg"

ns_dotdot=$(pkg ns-dotdot)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = ../src\n' >"$ns_dotdot/ct.pkg"

ns_missing=$(pkg ns-missing)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = src\n' >"$ns_missing/ct.pkg"

abs_inc=$(pkg abs-include)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\n' >"$abs_inc/ct.pkg"
printf 'cflags = -I /usr/local/include\n' >"$abs_inc/flags.ct"

# ---------------------------------------------------------------------------
# Negative fixtures: tag/version.
# ---------------------------------------------------------------------------
tag_mismatch=$(pkg tag-mismatch)
printf 'name = hello\npublisher = acme\nversion = 0.2.0\nns-root = .\n' >"$tag_mismatch/ct.pkg"
git -C "$tag_mismatch" init -q -b main
git -C "$tag_mismatch" add -A
git -C "$tag_mismatch" -c user.email=t@example.com -c user.name=t commit -qm init
git -C "$tag_mismatch" tag v0.1.0

# ---------------------------------------------------------------------------
# Negative fixtures: strict checks.
# ---------------------------------------------------------------------------
ns_mismatch=$(pkg strict-ns-mismatch)
mkdir -p "$ns_mismatch/lib"
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\n' >"$ns_mismatch/ct.pkg"
printf 'namespace acme;\n' >"$ns_mismatch/lib/Thing.h.ct"

dup_dep=$(pkg strict-dup-dep)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\ndep = std@^0.3.0\ndep = std@>=0.1.0\n' >"$dup_dep/ct.pkg"

bad_dep=$(pkg strict-bad-dep)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\ndep = std@>>1\n' >"$bad_dep/ct.pkg"

bad_req=$(pkg strict-bad-requires)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\nrequires = foo >= 1.0.0\n' >"$bad_req/ct.pkg"

bad_cb=$(pkg strict-bad-boundary)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\nc-boundary = loose\n' >"$bad_cb/ct.pkg"

artifact=$(pkg strict-artifact)
printf 'name = hello\npublisher = acme\nversion = 0.1.0\nns-root = .\n' >"$artifact/ct.pkg"
printf 'binary\n' >"$artifact/libhello.o"

# ---------------------------------------------------------------------------
# Cases.
# ---------------------------------------------------------------------------
echo "== base =="
run_case "minimal valid package" 0 "$valid"
run_case "relative -I is allowed" 0 "$rel_inc"
run_case "missing name" 1 "$no_name"
run_case "missing publisher" 1 "$no_pub"
run_case "missing version" 1 "$no_ver"
run_case "missing ns-root" 1 "$no_ns"
run_case "publisher = local" 1 "$pub_local"
run_case "name with whitespace" 1 "$bad_name"
run_case "version is not x.y.z" 1 "$bad_ver"
run_case "ns-root is absolute" 1 "$ns_abs"
run_case "ns-root contains .." 1 "$ns_dotdot"
run_case "ns-root directory is missing" 1 "$ns_missing"
run_case "absolute -I" 1 "$abs_inc"
run_case "HEAD tag differs from version" 1 "$tag_mismatch"
run_case "tag matches version" 0 "$tagged"

echo
echo "== strict =="
run_case "strict happy path" 0 "$strict_ok" --strict
run_case "namespace directory mismatch" 1 "$ns_mismatch" --strict
run_case "duplicate dep" 1 "$dup_dep" --strict
run_case "unparsable dep range" 1 "$bad_dep" --strict
run_case "requires names a package" 1 "$bad_req" --strict
run_case "c-boundary is not an enum" 1 "$bad_cb" --strict
run_case "build artifact in the tree" 1 "$artifact" --strict
run_case "strict flags are off by default" 0 "$ns_mismatch"

echo
echo "== no compiler on PATH =="
if env PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v ct >/dev/null 2>&1; then
    echo "  -> SKIP: this PATH still finds a 'ct'; choose a PATH without it"
elif out=$(env PATH=/usr/bin:/bin:/usr/sbin:/sbin "$check" "$valid" 2>&1); then
    printf '  -> rc=0 PASS  check runs without ct\n'
    passed=$((passed + 1))
else
    printf '  -> FAIL  check needs ct\n%s\n' "$out"
    failed=$((failed + 1))
fi

echo
printf 'summary: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1

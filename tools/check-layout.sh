#!/usr/bin/env bash
#
# check-layout.sh — enforce "unit directory = namespace" for every package.
#
# A unit that declares `namespace A::B;` must sit in `<package-root>/A/B/`.
# The compiler enforces the same rule with `ct build --ns-root <dir>`
# (D13 option A: validation, not derivation), but only for the inputs it is
# given and only when `--ns-root` is passed. This script is the package-level
# guard: it walks every `*.ct` unit under each package root, reads the
# file-scoped namespace declaration, and compares it with the unit's directory.
#
# Units without a `namespace` declaration are exempt: C bindings and their
# `.m.ct` shims keep the imported directory only, and adding a namespace to
# them would mangle their symbols.
#
# Usage:
#   tools/check-layout.sh                 # every package under the repo root
#   tools/check-layout.sh hal sqlite      # only the named package roots
#
# `CT_PKG_ROOT` selects the workspace root. When it is unset or empty the
# default is `tools/../..`, which is the layout of a normal checkout.
#
# Exit status: 0 when every namespaced unit matches, 1 otherwise. An empty scan
# set is a failure, not a pass: a workspace root with no `*/ct.pkg` usually
# means the package checkouts are missing, and reporting `ok: 0` there would
# hide a broken CI clone.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# This script lives in `index/tools/`; the packages sit two levels up, in the
# ct-pkg workspace root. `CT_PKG_ROOT` overrides that (CI checks out the
# packages somewhere else).
repo="${CT_PKG_ROOT:-$(cd "$here/../.." && pwd)}"

if [ $# -gt 0 ]; then
    packages=()
    for d in "$@"; do
        [ -d "$d" ] || {
            printf 'check-layout: %s is not a directory\n' "$d" >&2
            exit 1
        }
        pkg="$(cd "$d" && pwd)"
        [ -e "$pkg/ct.pkg" ] || {
            printf 'check-layout: %s has no ct.pkg\n' "$pkg" >&2
            exit 1
        }
        packages+=("$pkg")
    done
else
    packages=()
    for m in "$repo"/*/ct.pkg; do
        [ -e "$m" ] || continue
        packages+=("$(cd "$(dirname "$m")" && pwd)")
    done
fi

if [ "${#packages[@]}" -eq 0 ]; then
    printf 'check-layout: no packages found under %s (expected %s/*/ct.pkg)\n' \
        "$repo" "$repo" >&2
    printf 'check-layout: set CT_PKG_ROOT to the workspace root that holds the package checkouts\n' >&2
    exit 1
fi

checked=0
mismatched=0

for pkg in "${packages[@]}"; do
    name="$(basename "$pkg")"
    while IFS= read -r f; do
        rel="${f#"$pkg"/}"
        if [ "$rel" != "$f" ] && [[ "$rel" == */* ]]; then
            dir="${rel%/*}"
        else
            dir=""
        fi
        # The parser accepts only the file-scoped form and keeps the first
        # declaration, so take the first match too.
        ns="$(sed -n 's/^[[:space:]]*namespace[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_:]*\)[[:space:]]*;.*$/\1/p' "$f" | head -n 1)"
        [ -n "$ns" ] || continue
        want="$(printf '%s' "$ns" | sed 's/::/\//g')"
        checked=$((checked + 1))
        if [ "$dir" != "$want" ]; then
            printf 'FAIL  %s/%s: namespace %s expects directory %s\n' \
                "$name" "$rel" "$ns" "$want"
            mismatched=$((mismatched + 1))
        fi
    done < <(find "$pkg" -name '*.ct' -type f -print | sort)
done

if [ "$mismatched" -ne 0 ]; then
    printf '\n%d of %d namespaced units do not match their directory\n' \
        "$mismatched" "$checked" >&2
    exit 1
fi

printf 'ok: %d namespaced units match their directory\n' "$checked"

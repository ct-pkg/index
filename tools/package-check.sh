#!/usr/bin/env bash
#
# package-check.sh — read-only release lint for one ct package.
#
# Usage:
#   bash tools/package-check.sh <package-dir>
#   bash tools/package-check.sh --strict <package-dir>
#
# Exit status: 0 when the package passes, 1 otherwise. Nothing is written, no
# network is used, and no compiler is required: this is the shell replacement
# for the four read-only criteria of `ct pkg check`, plus the release rules
# that used to live only in prose.
#
# Base criteria (same strength as the CT-side check):
#   PK-1  ct.pkg exists and is readable
#   PK-2  name / publisher / version / ns-root are present, publisher != local
#   PK-5  ns-root is relative, has no '..', and is an existing directory
#   PK-8  no absolute -I under the package tree (skips .git, docs, issues,
#         battle, test, *.md, and files above 262144 bytes)
#
# Release criteria (default):
#   R1  name / publisher character set
#   R2  version is x.y.z
#   R3  tag <-> version consistency when the directory is a git checkout
#       (a missing repository or missing tag is a warning, never a failure)
#
# Strict criteria (--strict):
#   S1  every namespaced unit sits in <ns-root>/<namespace path>/
#   S2  dep specs parse and do not repeat a package
#   S3  requires parses as `ct` plus a version range
#   S4  c-boundary, when present, is `strict` or `allow`
#   S5  the package tree has no build artifacts, caches or vendor/ directories
#
# PK-8 and S5 skip the same directories: .git, docs, issues, battle, test.

set -uo pipefail

strict=0
dir=""

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) strict=1 ;;
        -h | --help)
            sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*)
            printf 'package-check: unknown option %s\n' "$1" >&2
            exit 2 ;;
        *)
            [ -z "$dir" ] || { printf 'package-check: one package directory at a time\n' >&2; exit 2; }
            dir=$1 ;;
    esac
    shift
done

if [ -z "$dir" ]; then
    printf 'usage: bash tools/package-check.sh [--strict] <package-dir>\n' >&2
    exit 2
fi
[ -d "$dir" ] || { printf 'package-check: not a directory: %s\n' "$dir" >&2; exit 1; }
dir=$(cd "$dir" && pwd)
manifest="$dir/ct.pkg"

failures=0
warnings=0
warn() {
    warnings=$((warnings + 1))
    printf 'warn  %-4s %s\n' "$1" "$2" >&2
}
bad() {
    failures=$((failures + 1))
    printf 'FAIL  %-4s %s: %s\n' "$1" "$2" "$3" >&2
}

# ---------------------------------------------------------------------------
# PK-1: the manifest must exist and be readable. Nothing below can run without
# it, so a failure here returns immediately.
# ---------------------------------------------------------------------------
if [ ! -f "$manifest" ] || [ ! -r "$manifest" ]; then
    bad PK-1 "$manifest" "cannot read the package manifest"
    exit 1
fi

# The identity keys are read exactly like `ct pkg check` reads them: the value
# is the first whitespace-delimited token after `=`. (Other keys keep the whole
# rest of the line, which is how `dep` ranges with spaces survive.)
manifest_token() {
    awk -v k="$1" '
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (line == "" || line ~ /^#/) next
            eq = index(line, "=")
            if (eq == 0) next
            key = substr(line, 1, eq - 1)
            gsub(/[ \t]+$/, "", key)
            if (key != k) next
            v = substr(line, eq + 1)
            sub(/^[ \t]+/, "", v)
            if (match(v, /[ \t#]/)) v = substr(v, 1, RSTART - 1)
            print v
            exit
        }
    ' "$manifest"
}

# Whole-value reader, matching the consumer's `read_manifest`: `key = value`
# keeps everything after `=`, trimmed. `#` only starts a comment at line start.
manifest_line_value() {
    awk -v k="$1" '
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (line == "" || line ~ /^#/) next
            eq = index(line, "=")
            if (eq == 0) next
            key = substr(line, 1, eq - 1)
            gsub(/[ \t]+$/, "", key)
            if (key != k) next
            v = substr(line, eq + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            print v
            exit
        }
    ' "$manifest"
}

manifest_values() {
    awk -v k="$1" '
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (line == "" || line ~ /^#/) next
            eq = index(line, "=")
            if (eq == 0) next
            key = substr(line, 1, eq - 1)
            gsub(/[ \t]+$/, "", key)
            if (key != k) next
            v = substr(line, eq + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            print v
        }
    ' "$manifest"
}

name=$(manifest_token name)
publisher=$(manifest_token publisher)
version=$(manifest_token version)
nsroot=$(manifest_token ns-root)

# ---------------------------------------------------------------------------
# PK-2: required identity.
# ---------------------------------------------------------------------------
if [ -z "$name" ]; then
    bad PK-2 "$manifest" "missing 'name'"
fi
if [ -z "$publisher" ]; then
    bad PK-2 "$manifest" "missing 'publisher'"
elif [ "$publisher" = local ]; then
    bad PK-2 "$manifest" "'publisher = local' is a placeholder, not a publisher"
fi
if [ -z "$version" ]; then
    bad PK-2 "$manifest" "missing 'version'"
fi
if [ -z "$nsroot" ]; then
    bad PK-2 "$manifest" "missing 'ns-root'"
fi
if [ "$failures" -ne 0 ]; then
    printf '\n%d criterion(s) failed\n' "$failures" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# R1: character set. `ct pkg check` only rejects '/' and '..' later in
# `pkg_store_commit`; doing it at release time keeps a bad identity out of the
# index in the first place.
# ---------------------------------------------------------------------------
identity_ok=1
for pair in "name:$name" "publisher:$publisher"; do
    key=${pair%%:*}
    value=${pair#*:}
    if ! [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        bad R1 "$manifest" "$key '$value' must match [A-Za-z0-9][A-Za-z0-9._-]*"
        identity_ok=0
        continue
    fi
    case "$value" in
        *..*)
            bad R1 "$manifest" "$key '$value' must not contain '..'"
            identity_ok=0 ;;
        */*)
            bad R1 "$manifest" "$key '$value' must not contain '/'"
            identity_ok=0 ;;
    esac
done

# ---------------------------------------------------------------------------
# R2: version shape. The index generator and the tag rule both assume x.y.z.
# ---------------------------------------------------------------------------
if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    bad R2 "$manifest" "version '$version' must be x.y.z"
fi

# ---------------------------------------------------------------------------
# PK-5: ns-root shape and directory.
# ---------------------------------------------------------------------------
ns_ok=1
if [ "${nsroot#/}" != "$nsroot" ]; then
    bad PK-5 "$manifest" "ns-root '$nsroot' must be relative"
    ns_ok=0
fi
case "$nsroot" in
    *..*)
        bad PK-5 "$manifest" "ns-root '$nsroot' must not contain '..'"
        ns_ok=0 ;;
esac
if [ "$ns_ok" = 1 ] && [ ! -d "$dir/$nsroot" ]; then
    bad PK-5 "$dir/$nsroot" "ns-root '$nsroot' is not a directory"
    ns_ok=0
fi

# ---------------------------------------------------------------------------
# PK-8: no absolute -I in the package tree.
# ---------------------------------------------------------------------------
# Directory names that are not build inputs. Kept identical to `ct pkg check`
# so the shell and the compiler agree on what a package tree contains.
find_pkg_files() {
    find -L "$dir" \
        \( -name .git -o -name docs -o -name issues -o -name battle -o -name test \) -prune \
        -o -type f -size -262145c ! -name '*.md' -print 2>/dev/null
}

# Artifacts are checked without the size and extension filters: a large object
# file is exactly what S5 is meant to catch.
find_tree_files() {
    find -L "$dir" \
        \( -name .git -o -name docs -o -name issues -o -name battle -o -name test \) -prune \
        -o -type f -print 2>/dev/null
}

abs_i_scan() {
    # Same trigger as the compiler: `-I` at the start of a line or after a
    # space, tab or quote, followed by optional blanks and '/'.
    awk '
        {
            line = $0
            pos = 1
            while (1) {
                i = index(substr(line, pos), "-I")
                if (i == 0) break
                at = pos + i - 1
                pre = (at == 1) ? "" : substr(line, at - 1, 1)
                if (at == 1 || pre == " " || pre == "\t" || pre == "\"" || pre == "'"'"'") {
                    rest = substr(line, at + 2)
                    sub(/^[ \t]+/, "", rest)
                    if (substr(rest, 1, 1) == "/") { print FNR; exit }
                }
                pos = at + 2
            }
        }
    ' "$1"
}

if [ "$ns_ok" = 1 ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        hit=$(abs_i_scan "$f" | head -n 1)
        if [ -n "$hit" ]; then
            bad PK-8 "$f:$hit" "absolute -I is not allowed in a package"
        fi
    done < <(find_pkg_files)
fi

# ---------------------------------------------------------------------------
# R3: tag <-> version. Only meaningful in a git checkout; a working copy that
# has not been tagged yet is a warning, because `ct-pkg/index` tags at release
# time and a developer's pre-release tree is a normal state.
# ---------------------------------------------------------------------------
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    head_tags=$(git -C "$dir" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]' || true)
    if [ -n "$head_tags" ]; then
        if ! printf '%s\n' "$head_tags" | grep -qx "v$version"; then
            tagged=$(printf '%s' "$head_tags" | tr '\n' ' ')
            bad R3 "$manifest" "HEAD is tagged $tagged but ct.pkg says version '$version' (expected v$version)"
        fi
    elif git -C "$dir" tag -l "v$version" 2>/dev/null | grep -q .; then
        :
    else
        warn R3 "HEAD is not tagged and v$version does not exist yet; tag before publishing"
    fi
else
    warn R3 "$dir is not a git checkout; skipped the tag/version check"
fi

# ---------------------------------------------------------------------------
# S1-S5: strict release checks.
# ---------------------------------------------------------------------------
if [ "$strict" = 1 ]; then
    # S1: namespace directory must equal <ns-root>/<namespace path>.
    if [ "$ns_ok" = 1 ]; then
        nsdir="$dir/$nsroot"
        while IFS= read -r f; do
            rel=${f#"$nsdir"/}
            case "$rel" in
                */*) want_dir=${rel%/*} ;;
                *) want_dir="" ;;
            esac
            ns=$(sed -n 's/^[[:space:]]*namespace[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_:]*\)[[:space:]]*;.*$/\1/p' "$f" | head -n 1)
            [ -n "$ns" ] || continue
            want=${ns//::/\/}
            if [ "$want_dir" != "$want" ]; then
                bad S1 "$f" "namespace $ns expects directory '$want' under ns-root, found '$want_dir'"
            fi
        done < <(find -L "$nsdir" \
                    \( -name .git -o -name docs -o -name issues -o -name battle -o -name test \) -prune \
                    -o -type f -name '*.ct' -print 2>/dev/null | sort)
    fi

    # S2: dep = pkg[@range], no duplicate package.
    range_ok() {
        local r=$1 c v norm
        [ -n "$r" ] || return 1
        case "$r" in *'||'*) return 1 ;; esac
        # The compiler allows blanks between an operator and its version
        # (`>= 0.54.0`), so fold them before splitting clauses.
        norm=$(printf '%s' "$r" | sed -E 's/(>=|<=|>|<|=|\^|~)[[:space:]]+/\1/g')
        # Intentional word splitting: clauses are separated by blanks.
        for c in $norm; do
            [ "$c" = "*" ] && continue
            case "$c" in
                '>='* | '<='*) v=${c#??} ;;
                '>'* | '<'* | '='* | '^'* | '~'*) v=${c#?} ;;
                *) v=$c ;;
            esac
            [[ $v =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
        done
        return 0
    }

    deps_seen=" "
    while IFS= read -r spec; do
        spec=$(printf '%s' "$spec" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$spec" ] || continue
        dep_path=$spec
        dep_range=""
        if [[ $spec == *@* ]]; then
            dep_path=${spec%@*}
            dep_range=${spec##*@}
        fi
        if [ -z "$dep_path" ] || ! [[ $dep_path =~ ^[A-Za-z0-9_.~:/-]+$ ]]; then
            bad S2 "$manifest" "dep '$spec' has an invalid package path"
            continue
        fi
        case "$dep_path" in
            -*) bad S2 "$manifest" "dep '$spec' must not start with '-'"; continue ;;
            *..*) bad S2 "$manifest" "dep '$spec' must not contain '..'"; continue ;;
        esac
        if [ -n "$dep_range" ] && ! range_ok "$dep_range"; then
            bad S2 "$manifest" "dep '$spec' has an unparsable range '$dep_range'"
            continue
        fi
        case "$deps_seen" in
            *" $dep_path "*)
                bad S2 "$manifest" "dep '$dep_path' is declared more than once"
                continue ;;
        esac
        deps_seen="$deps_seen$dep_path "
    done < <(manifest_values dep)

    # S3: requires = ct <range>.
    req=$(manifest_line_value requires)
    if [ -n "$req" ]; then
        if ! [[ $req =~ ^[[:space:]]*ct($|[[:space:]]|[<>=^~*]) ]]; then
            bad S3 "$manifest" "requires '$req' must start with 'ct' (use dep for packages)"
        else
            rest=${req#ct}
            rest=$(printf '%s' "$rest" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            if [ -z "$rest" ]; then
                bad S3 "$manifest" "requires 'ct' needs a version range"
            elif ! range_ok "$rest"; then
                bad S3 "$manifest" "requires '$req' has an unparsable range '$rest'"
            fi
        fi
    fi

    # S4: c-boundary is an enum when present.
    cb=$(manifest_token c-boundary)
    if [ -n "$cb" ] && [ "$cb" != strict ] && [ "$cb" != allow ]; then
        bad S4 "$manifest" "c-boundary '$cb' must be 'strict' or 'allow'"
    fi

    # S5: no build products, caches or vendor trees.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            *.o | *.a | *.so | *.so.* | *.dylib | *.dll | *.exe | *.obj | *.lo | *.la | *.pyc)
                bad S5 "$f" "build artifact in the package tree" ;;
        esac
    done < <(find_tree_files)
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        bad S5 "$d" "cache or vendor directory in the package tree"
    done < <(find -L "$dir" \
                \( -name .git -o -name docs -o -name issues -o -name battle -o -name test \) -prune \
                -o -type d \( -name .ctcache -o -name vendor -o -name build -o -name dist -o -name target \) -print 2>/dev/null)
fi

# ---------------------------------------------------------------------------
# Result. The first line stays byte-compatible with `ct pkg check` so an
# existing wrapper that greps for it keeps working.
# ---------------------------------------------------------------------------
if [ "$failures" -ne 0 ]; then
    printf '\n%d criterion(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'ok: 4 criteria\n'
printf 'ok: release lint (3 criteria)\n'
if [ "$strict" = 1 ]; then
    printf 'ok: strict lint (5 criteria)\n'
    printf 'ok: 12 criteria\n'
else
    printf 'ok: 7 criteria\n'
fi

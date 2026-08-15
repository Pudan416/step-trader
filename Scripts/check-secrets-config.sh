#!/bin/bash
#
# Guards the Config/Secrets.xcconfig layer (§6.1).
#
# Two failure modes this catches, both of which shipped silently before:
#
#   1. Drift — an Info.plist starts referencing a new $(VAR) that lives in the
#      secrets layer, but Secrets.xcconfig.template is never updated. Every
#      machine without that key builds with an empty value.
#
#   2. Placeholder escape — Secrets.xcconfig gets overwritten by the template
#      (or ci_post_clone.sh runs without its env secrets set), so the build
#      bakes `https://YOUR_PROJECT.supabase.co` into Info.plist. The runtime
#      guard in SupabaseConfig does NOT catch this: the placeholder host ends
#      in `.supabase.co`, so it passes the Release host assertion and the app
#      just fails every request against a domain that does not resolve.
#
# Usage:
#   scripts/check-secrets-config.sh                    # drift + tracking checks
#   scripts/check-secrets-config.sh --no-placeholders  # also reject placeholders
#
# The default mode is safe to run in CI, which deliberately builds with the
# template (unit tests never hit the network). Use --no-placeholders for any
# build that is meant to reach a real backend.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PROJECT="Steps4.xcodeproj"
TEMPLATE="Config/Secrets.xcconfig.template"
SECRETS="Config/Secrets.xcconfig"

reject_placeholders=0
[[ "${1:-}" == "--no-placeholders" ]] && reject_placeholders=1

fail() { printf '❌ %s\n' "$1" >&2; failed=1; }
failed=0

[[ -f "$TEMPLATE" ]] || { printf '❌ missing %s\n' "$TEMPLATE" >&2; exit 1; }

# --- 1. The real secrets file must never be committed --------------------------
if git ls-files --error-unmatch "$SECRETS" >/dev/null 2>&1; then
    fail "$SECRETS is tracked by git — it holds per-environment keys and must stay ignored."
fi

# --- 2. Collect the placeholder values the template ships ----------------------
# `$()` is an xcconfig escape that expands to nothing; it only exists to stop
# `//` being read as a comment. Strip it so values compare against resolved ones.
declare -a keys=() placeholders=()
while IFS= read -r line; do
    key="${line%%=*}"; key="${key// /}"
    value="${line#*=}"; value="${value# }"; value="${value//\$()/}"
    keys+=("$key"); placeholders+=("$value")
done < <(grep -E '^[A-Z_][A-Z0-9_]* *=' "$TEMPLATE")

[[ ${#keys[@]} -gt 0 ]] || { printf '❌ %s defines no keys\n' "$TEMPLATE" >&2; exit 1; }

# --- 3. Resolve build settings for every target in one pass --------------------
settings="$(xcodebuild -project "$PROJECT" -showBuildSettings 2>/dev/null || true)"
[[ -n "$settings" ]] || { printf '❌ xcodebuild -showBuildSettings produced no output\n' >&2; exit 1; }

resolved() { # resolved KEY -> first non-empty value across targets
    awk -v k="$1" '
        $1 == k && $2 == "=" {
            v = ""
            for (i = 3; i <= NF; i++) v = v (i > 3 ? " " : "") $i
            if (v != "") { print v; exit }
        }' <<<"$settings"
}

# --- 4. Drift: every $(VAR) an Info.plist references must resolve --------------
# Tracked plists only — build/ and worktree copies are not the source of truth.
while IFS= read -r plist; do
    while IFS= read -r ref; do
        [[ -n "$ref" ]] || continue
        if [[ -z "$(resolved "$ref")" ]]; then
            fail "$plist references \$($ref) but it resolves to nothing. Add it to $TEMPLATE."
        fi
    done < <(grep -oE '\$\([A-Z_][A-Z0-9_]*\)' "$plist" | tr -d '$()' | sort -u)
done < <(git ls-files '*Info.plist')

# --- 5. Every template key must still be referenced ----------------------------
for key in "${keys[@]}"; do
    if ! git grep -qF "\$($key)" -- '*Info.plist' 2>/dev/null; then
        fail "$TEMPLATE defines $key but no Info.plist references \$($key) — stale entry?"
    fi
done

# --- 6. Placeholder escape ------------------------------------------------------
if [[ $reject_placeholders -eq 1 ]]; then
    for i in "${!keys[@]}"; do
        key="${keys[$i]}"; placeholder="${placeholders[$i]}"
        if [[ "$(resolved "$key")" == "$placeholder" ]]; then
            fail "$key still holds the template placeholder ('$placeholder'). This build cannot reach a real backend."
        fi
    done
fi

if [[ $failed -eq 1 ]]; then
    printf '\nSecrets config check FAILED.\n' >&2
    exit 1
fi

printf '✅ Secrets config OK (%d keys%s).\n' "${#keys[@]}" \
    "$([[ $reject_placeholders -eq 1 ]] && echo ', no placeholders' || echo '')"

#!/bin/sh
# Xcode Cloud: create Secrets.xcconfig from template so the build can succeed.
# Set the Supabase keys as Xcode Cloud workflow secrets;
# this script substitutes them into Secrets.xcconfig before the build.
set -e
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-.}"
CONFIG_DIR="${REPO_ROOT}/Config"
SECRETS="${CONFIG_DIR}/Secrets.xcconfig"

if [ ! -f "${SECRETS}" ]; then
  cp "${CONFIG_DIR}/Secrets.xcconfig.template" "${SECRETS}"
fi

substitute() {
  key="$1"
  value="$2"
  if [ -n "${value}" ]; then
    # xcconfig treats `//` as a start-of-comment, so a bare `https://host` is
    # read as `https:` and the host is silently dropped. `$()` expands to
    # nothing and breaks the pair up — the same trick the template uses.
    value=$(printf '%s\n' "${value}" | sed 's|//|/$()/|g')
    # Escape sed metacharacters in the value (slashes).
    escaped=$(printf '%s\n' "${value}" | sed 's/[\/&]/\\&/g')
    sed -i '' "s|^${key} = .*|${key} = ${escaped}|" "${SECRETS}"
  fi
}

substitute "SUPABASE_URL" "${SUPABASE_URL:-}"
substitute "SUPABASE_ANON_KEY" "${SUPABASE_ANON_KEY:-}"

# `substitute` is a no-op when its env var is unset, which silently leaves the
# template placeholder in the file — and the Release host assertion in
# SupabaseConfig does not catch it, because `YOUR_PROJECT.supabase.co` ends in
# `.supabase.co`. Such a build installs fine and then fails every single
# request against a domain that does not resolve. Fail the build instead.
assert_substituted() {
  key="$1"
  actual=$(sed -n "s|^${key} = ||p" "${SECRETS}")
  placeholder=$(sed -n "s|^${key} = ||p" "${CONFIG_DIR}/Secrets.xcconfig.template")
  if [ -z "${actual}" ] || [ "${actual}" = "${placeholder}" ]; then
    echo "ci_post_clone: ${key} is still the template placeholder." >&2
    echo "Set it as an Xcode Cloud workflow environment variable (mark it secret)." >&2
    exit 1
  fi
}

assert_substituted "SUPABASE_URL"
assert_substituted "SUPABASE_ANON_KEY"

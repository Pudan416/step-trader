#!/bin/sh
# Xcode Cloud: create Secrets.xcconfig from template so the build can succeed.
# Set REVENUECAT_API_KEY (and Supabase keys) as Xcode Cloud workflow secrets;
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
    # Escape sed metacharacters in the value (slashes).
    escaped=$(printf '%s\n' "${value}" | sed 's/[\/&]/\\&/g')
    sed -i '' "s|^${key} = .*|${key} = ${escaped}|" "${SECRETS}"
  fi
}

substitute "REVENUECAT_API_KEY" "${REVENUECAT_API_KEY:-}"
substitute "SUPABASE_URL" "${SUPABASE_URL:-}"
substitute "SUPABASE_ANON_KEY" "${SUPABASE_ANON_KEY:-}"

#!/bin/sh
# Xcode Cloud: create Secrets.xcconfig from template so the build can succeed.
# Real keys can be set via Xcode Cloud environment variables and substituted here if needed.
set -e
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-.}"
CONFIG_DIR="${REPO_ROOT}/Config"
if [ ! -f "${CONFIG_DIR}/Secrets.xcconfig" ]; then
  cp "${CONFIG_DIR}/Secrets.xcconfig.template" "${CONFIG_DIR}/Secrets.xcconfig"
fi

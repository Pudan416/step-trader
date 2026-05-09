#!/usr/bin/env bash
# Replace the canvas "heart 1" ray asset with your black soft-beam PNG.
# Usage (from anywhere):
#   bash Scripts/copy-heart-beam.sh /path/to/Group_72.png
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../StepsTrader/Assets.xcassets" && pwd)"
SRC="${1:?pass path to your PNG}"
DEST="$HERE/heart 1.imageset/heart 1.png"
cp "$SRC" "$DEST"
echo "OK: $DEST"

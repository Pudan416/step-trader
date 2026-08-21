#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

required=(
  "StepsTrader/Views/GenerativeCanvasView.swift"
  "StepsTrader/Experiments/DayObjects/DayObjectsView.swift"
  "StepsTrader/Metal/DayObjectsActorShader.metal"
  "StepsTrader/Metal/DayObjectsMeshGradientShader.metal"
  "StepsTrader/Metal/DayObjectsPostShader.metal"
)

for file in "${required[@]}"; do
  git ls-files --error-unmatch "$file" >/dev/null 2>&1 || {
    printf 'missing required retained file: %s\n' "$file" >&2
    exit 1
  }
done

forbidden='RichCanvas|RichFigure|RichRender|GenerativeScene|CanvasAtmosphere|DayRays|FormulaLab'
if matches="$(git grep -n -E "$forbidden" -- StepsTrader Steps4Tests Steps4UITests Steps4.xcodeproj 2>/dev/null)"; then
  printf 'obsolete experiment references remain:\n%s\n' "$matches" >&2
  exit 1
fi

route_cases="$(sed -n 's/^[[:space:]]*case \([A-Za-z][A-Za-z0-9]*\)$/\1/p' StepsTrader/Experiments/ExperimentalLabRoute.swift)"
[[ "$route_cases" == "dayObjects" ]] || {
  printf 'expected only dayObjects route, found: %s\n' "$route_cases" >&2
  exit 1
}

feature_flags="$(sed -n 's/^[[:space:]]*static let \([A-Za-z][A-Za-z0-9]*Lab\) = .*/\1/p' StepsTrader/Utilities/ExperimentalFeatures.swift | sort -u)"
[[ "$feature_flags" == "dayObjectsLab" ]] || {
  printf 'expected only dayObjectsLab flag, found: %s\n' "$feature_flags" >&2
  exit 1
}

printf 'Day Objects is the only tracked experiment.\n'

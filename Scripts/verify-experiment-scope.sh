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

expected_experiment_files="$(cat <<'EOF'
StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift
StepsTrader/Experiments/DayObjects/DayObjectComposition.swift
StepsTrader/Experiments/DayObjects/DayObjectPalette.swift
StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift
StepsTrader/Experiments/DayObjects/DayObjectScene.swift
StepsTrader/Experiments/DayObjects/DayObjectTypes.swift
StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift
StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift
StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift
StepsTrader/Experiments/DayObjects/DayObjectsView.swift
StepsTrader/Experiments/DayObjects/ModernPaletteCatalog.swift
StepsTrader/Experiments/ExperimentalLabRoute.swift
EOF
)"
actual_experiment_files="$(git ls-files -- StepsTrader/Experiments | LC_ALL=C sort)"
[[ "$actual_experiment_files" == "$expected_experiment_files" ]] || {
  printf 'unexpected tracked experiment files. expected:\n%s\nactual:\n%s\n' \
    "$expected_experiment_files" "$actual_experiment_files" >&2
  exit 1
}

forbidden='reach[[:space:]_-]*canvas|rich[[:space:]_-]*(canvas|figure|render)|generative[[:space:]_-]*scene|canvas[[:space:]_-]*atmosphere|day[[:space:]_-]*rays|formula[[:space:]_-]*lab'
if matches="$(git grep -i -n -E "$forbidden" -- StepsTrader Steps4Tests Steps4UITests Steps4.xcodeproj 2>/dev/null)"; then
  printf 'obsolete experiment references remain:\n%s\n' "$matches" >&2
  exit 1
fi

route_file="StepsTrader/Experiments/ExperimentalLabRoute.swift"
route_guard="$(sed -n '1s/^[[:space:]]*//; 1s/[[:space:]]*$//; 1p' "$route_file")"
[[ "$route_guard" == "#if DEBUG || INTERNAL_BUILD" ]] || {
  printf 'expected Debug/Internal route guard, found: %s\n' "$route_guard" >&2
  exit 1
}

route_case_lines="$(
  { grep -E -o 'case[[:space:]]+[^;{}]+' "$route_file" || true; } \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
)"
[[ "$route_case_lines" == "case dayObjects" ]] || {
  printf 'expected exactly one bare route case (`case dayObjects`), found: %s\n' "$route_case_lines" >&2
  exit 1
}

feature_flags="$(
  sed -E -n 's/^.*static[[:space:]]+let[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/p' \
    StepsTrader/Utilities/ExperimentalFeatures.swift | LC_ALL=C sort -u
)"
[[ "$feature_flags" == "dayObjectsLab" ]] || {
  printf 'expected exactly one experimental static-let flag (`dayObjectsLab`), found: %s\n' "$feature_flags" >&2
  exit 1
}

appearance_file="StepsTrader/Views/Settings/SettingsAppearancePage.swift"
gated_row_count="$(grep -E -c '^[[:space:]]*if[[:space:]]+ExperimentalFeatures\.dayObjectsLab[[:space:]]*\{[[:space:]]*$' "$appearance_file" || true)"
property_count="$(grep -E -c '^[[:space:]]*private[[:space:]]+var[[:space:]]+dayObjectsLabSection[[:space:]]*:[[:space:]]*some[[:space:]]+View[[:space:]]*\{[[:space:]]*$' "$appearance_file" || true)"
day_objects_section_references="$( { grep -E -o 'dayObjectsLabSection' "$appearance_file" || true; } | wc -l | tr -d '[:space:]')"
appearance_lab_flags="$(
  { grep -E -o 'ExperimentalFeatures\.[A-Za-z_][A-Za-z0-9_]*Lab' "$appearance_file" || true; } \
    | sed 's/^ExperimentalFeatures\.//' | LC_ALL=C sort -u
)"
appearance_lab_sections="$(
  { grep -E -o '[A-Za-z_][A-Za-z0-9_]*LabSection' "$appearance_file" || true; } \
    | LC_ALL=C sort -u
)"
[[ "$gated_row_count" == "1" \
   && "$property_count" == "1" \
   && "$day_objects_section_references" == "2" \
   && "$appearance_lab_flags" == "dayObjectsLab" \
   && "$appearance_lab_sections" == "dayObjectsLabSection" ]] || {
  printf 'expected exactly one gated Day Objects Appearance lab row/property; got gate=%s property=%s references=%s flags=%s sections=%s\n' \
    "$gated_row_count" "$property_count" "$day_objects_section_references" \
    "$appearance_lab_flags" "$appearance_lab_sections" >&2
  exit 1
}

app_file="StepsTrader/StepsTraderApp.swift"
app_launch_guards="$(
  sed -n '/^[[:space:]]*var body: some Scene {/,/^[[:space:]]*@ViewBuilder/ {
    /^[[:space:]]*#if[[:space:]]/ {
      s/^[[:space:]]*//
      s/[[:space:]]*$//
      p
    }
  }' "$app_file"
)"
app_launch_route_count="$(
  sed -n '/^[[:space:]]*var body: some Scene {/,/^[[:space:]]*@ViewBuilder/ p' "$app_file" \
    | grep -E -c 'ExperimentalLabRoute\.current' || true
)"
app_shortcut_comment_count="$(grep -F -c 'Debug/Internal shortcut: `-uiLab dayObjects` opens the retained experiment' "$app_file" || true)"
[[ "$app_launch_guards" == "#if DEBUG || INTERNAL_BUILD" \
   && "$app_launch_route_count" == "1" \
   && "$app_shortcut_comment_count" == "1" ]] || {
  printf 'expected one Debug/Internal Day Objects launch hook; got guards=%s route-count=%s comment-count=%s\n' \
    "$app_launch_guards" "$app_launch_route_count" "$app_shortcut_comment_count" >&2
  exit 1
}

printf 'Day Objects is the only tracked experiment.\n'

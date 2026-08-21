# Day Objects Only Experiment Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the active Canvas branches from `main` so Day Objects is the only experiment, publish clean stacked PRs, and provide one preview branch that runs through the ordinary `Steps4` scheme.

**Architecture:** Reconstruct the Canvas UI history from known production commits instead of merging and reverting obsolete laboratories. Build Day Objects as a selective final-state transplant on top of that clean Canvas head, add a tracked scope guard, then update PR #18 and publish a separate draft Day Objects PR.

**Tech Stack:** Git worktrees and private refs, GitHub CLI, Swift 6 / SwiftUI, Metal, Xcode project files, XCTest and XCUITest, Bash scope verification.

**Spec:** `docs/superpowers/specs/2026-08-22-day-objects-only-cleanup-design.md`

## Global Constraints

- Keep `StepsTrader/Views/GenerativeCanvasView.swift` and the production Canvas tab.
- Keep production stipple removal commit `23e8d31e0804cb711948ca95a10808bb7c23bd88`.
- Keep the 26 commits in `codex/remove-stipple..origin/feat/canvas-ui-simplification`.
- Exclude the 17 Rich Canvas commits after `23e8d31e`, commit `2d2f679e1aa7d26c12c507894d5027815147491e`, and every Formula Lab commit.
- Keep only `StepsTrader/Experiments/DayObjects/` under `StepsTrader/Experiments/`.
- Keep only the `dayObjects` debug lab route and `dayObjectsLab` experiment flag.
- Never stage `Config/Secrets.xcconfig`, `xcuserdata`, `.impeccable`, `.superpowers`, simulator captures, or generated image artifacts.
- Update published history only with `--force-with-lease` pinned to the observed remote SHA.
- Do not remove an old worktree or branch until its replacement is pushed, tested, and represented by the expected GitHub PR diff.
- The primary dirty checkout remains untouched until its unrelated Me, Feeds, typography, canvas-fill, and rendering changes are split later.

---

## File Map

**Canvas UI clean branch**

- Existing Canvas production and UI files changed by commit `23e8d31e` and the 26 Canvas UI commits.
- `docs/superpowers/specs/2026-08-22-day-objects-only-cleanup-design.md` records why history is reconstructed.
- No file under `StepsTrader/Experiments/` is introduced on this branch.

**Day Objects clean branch**

- `Scripts/verify-experiment-scope.sh` enforces the one-experiment boundary.
- `StepsTrader/Experiments/ExperimentalLabRoute.swift` owns the single Debug launch route.
- `StepsTrader/Utilities/ExperimentalFeatures.swift` owns the single build-gated lab flag.
- `StepsTrader/Experiments/DayObjects/*.swift` contains the retained Day Objects model, composition, choreography, render-frame, renderer, view, and lab UI.
- `StepsTrader/Metal/DayObjectsActorShader.metal`, `DayObjectsMeshGradientShader.metal`, and `DayObjectsPostShader.metal` contain the retained static shader passes.
- `StepsTrader/StepsTraderApp.swift` routes `-uiLab dayObjects` to the lab without changing Release launch behavior.
- `StepsTrader/Views/Settings/SettingsAppearancePage.swift` exposes the sole lab entry.
- `StepsTrader/Models/GradientPalette.swift` exposes the four canonical palette colors consumed by Day Objects.
- `StepsTrader/Localizable.xcstrings` contains only the Day Objects strings added by the retained lab.
- `Steps4.xcodeproj/project.pbxproj` registers only Day Objects experiment files plus the single route and flag.
- `Steps4Tests/DayObject*.swift` and `Steps4UITests/DayObjectsLabUITests.swift` verify the retained feature.

---

### Task 1: Reconstruct the Clean Canvas UI Head

**Files:**
- Preserve: `docs/superpowers/specs/2026-08-22-day-objects-only-cleanup-design.md`
- Modify through cherry-picks: the exact files recorded by commit `23e8d31e` and the Canvas UI range
- Test: `Steps4Tests/CanvasEnergyStatusTests.swift`
- Test: `Steps4Tests/CanvasPresentationStateTests.swift`
- Test: `Steps4Tests/CanvasRemixTests.swift`
- Test: `Steps4UITests/CanvasSimplificationUITests.swift`

**Interfaces:**
- Consumes: `main` at `45b3235b8ec5a8a935788d0b83ae99403fa8cd03`, old PR #18 head at `828e2b5a66b7ed368bcf942b11b53d94f3c614b5`
- Produces: local branch `codex/canvas-ui-clean` with no experiment files and a testable Canvas UI diff against `main`

- [ ] **Step 1: Confirm every source tip before writing safety refs**

Run:

```bash
test "$(git rev-parse main)" = 45b3235b8ec5a8a935788d0b83ae99403fa8cd03
test "$(git rev-parse origin/feat/canvas-ui-simplification)" = 828e2b5a66b7ed368bcf942b11b53d94f3c614b5
test "$(git rev-parse codex/remove-stipple)" = 8e5c1328cd513dd5ae062548dadd4253cd139420
test "$(git rev-parse codex/ai-formula-lab)" = c4033b859f8ef7acf14f50d65581f2ab970047f1
test "$(git rev-parse codex/day-objects-choreography)" = d9141cdce8d7b332f5748fc88134260c4091cc9e
test -z "$(git status --porcelain)"
```

Expected: every command exits zero and prints nothing.

- [ ] **Step 2: Preserve old committed tips outside the branch namespace**

Run:

```bash
git update-ref refs/codex-backup/2026-08-22/pr18 828e2b5a66b7ed368bcf942b11b53d94f3c614b5
git update-ref refs/codex-backup/2026-08-22/remove-stipple 8e5c1328cd513dd5ae062548dadd4253cd139420
git update-ref refs/codex-backup/2026-08-22/formula-lab c4033b859f8ef7acf14f50d65581f2ab970047f1
git update-ref refs/codex-backup/2026-08-22/day-objects d9141cdce8d7b332f5748fc88134260c4091cc9e
git for-each-ref --format='%(refname) %(objectname)' refs/codex-backup/2026-08-22/
```

Expected: four refs with the four exact SHAs above. They do not appear in `git branch`.

- [ ] **Step 3: Rename the isolated implementation branch**

Run:

```bash
git branch -m codex/canvas-ui-clean
git status --short --branch
```

Expected: `## codex/canvas-ui-clean` and no file changes.

- [ ] **Step 4: Apply only the retained production stipple removal**

Run:

```bash
git cherry-pick 23e8d31e0804cb711948ca95a10808bb7c23bd88
```

Expected: one clean cherry-pick titled `fix: remove stipple texture from the canvas`; none of the following 17 Rich Canvas commits is applied.

- [ ] **Step 5: Apply the complete clean Canvas UI range in order**

Run:

```bash
git cherry-pick \
  9fa6c8f4d9fd5b1809a9721f16dfc141d9782ca4 \
  0b6021398cc3900c6cc7e4cd21a2cb11c3e1fc3a \
  ad5e9425fa3f27657f5189ffcb6c300cfff5db0b \
  ffce5bcc354e149b38a489627f7f4584ce83ce04 \
  f88ceec43c912e5923111f4ddad2137b210181c7 \
  4097fe5e4312e0b1f56cc8a1c29fce4be93d155d \
  8a93d5d063a1ebe2f4fa972e8afef8e7f92b622e \
  4e5725297d3533192158d51280bbca034e33fc9d \
  4d92bc71da87d9ecc39022e59c18543ab939c309 \
  13c307f063697d525a14464af55f0a6b7b3c8027 \
  48d15384b1e9641fa35be950254655052c216535 \
  1c068ea57568ad9cd71b14c14acd5a883c6d3149 \
  bd1983c660b010a62f72174f4bf9fd40528e6e78 \
  979ae135d192f918b3e5055f730d2bda0966a865 \
  c4b2020d64d81d0a2ac345cfd8d199cd022535b9 \
  e3a097d6b08bb97aa09be8003860be0698a9441d \
  3cf1fc99174839b0fbed60585e92eb972cd0f7a5 \
  c41e4d0ddfe5dea833d01a2fe5f68ce77326d1dd \
  9fc05626e4c9b26f93be4ac7455307c1123815e8 \
  08fb11ae270b6952429a85da05270c1b9f2a7d20 \
  a7699dde553524a298229ebe735632a515a98af6 \
  87b8442f94fd0018deb50be9b52b5a217637e3c7 \
  a0ef4c349e4be35522cadc308bb9a70126868669 \
  633e2181ada05f16b99f4fa286a60d5937b6bddd \
  81f40218ef30fc784df35bdef25b4c8d88d226f3 \
  828e2b5a66b7ed368bcf942b11b53d94f3c614b5
```

Expected: 26 commits apply. Commit `2d2f679e1aa7d26c12c507894d5027815147491e` is not part of the command.

- [ ] **Step 6: Prove the reconstructed Canvas head contains no lab code**

Run:

```bash
test -z "$(git ls-files 'StepsTrader/Experiments/**')"
test -z "$(git grep -n -E 'RichCanvas|RichFigure|RichRender|GenerativeScene|CanvasAtmosphere|DayRays|FormulaLab' -- StepsTrader Steps4Tests Steps4UITests Steps4.xcodeproj || true)"
git ls-files --error-unmatch StepsTrader/Views/GenerativeCanvasView.swift
git diff --check main...HEAD
```

Expected: only the retained `GenerativeCanvasView.swift` path is printed.

- [ ] **Step 7: Run the scoped Canvas unit tests**

Run:

```bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:Steps4Tests/CanvasEnergyStatusTests \
  -only-testing:Steps4Tests/CanvasPresentationStateTests \
  -only-testing:Steps4Tests/CanvasRemixTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Run the Canvas UI regression target**

Run:

```bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:Steps4UITests/CanvasSimplificationUITests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `** TEST SUCCEEDED **` and no failed Canvas simplification UI test.

### Task 2: Define the Day Objects-Only Scope as an Executable Test

**Files:**
- Create: `Scripts/verify-experiment-scope.sh`

**Interfaces:**
- Consumes: clean `codex/canvas-ui-clean` head from Task 1
- Produces: `codex/day-objects-clean` and an executable contract that fails until Day Objects is present and fails whenever an obsolete laboratory returns

- [ ] **Step 1: Create the clean Day Objects branch**

Run:

```bash
git switch -c codex/day-objects-clean codex/canvas-ui-clean
```

Expected: `Switched to a new branch 'codex/day-objects-clean'`.

- [ ] **Step 2: Write the failing experiment-scope verifier**

Create `Scripts/verify-experiment-scope.sh` with exactly:

```bash
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
```

- [ ] **Step 3: Make the verifier executable and prove it fails for the missing retained experiment**

Run:

```bash
chmod +x Scripts/verify-experiment-scope.sh
Scripts/verify-experiment-scope.sh
```

Expected: exit 1 with `missing required retained file: StepsTrader/Experiments/DayObjects/DayObjectsView.swift`.

- [ ] **Step 4: Commit the failing contract**

Run:

```bash
git add -- Scripts/verify-experiment-scope.sh
git commit -m "test: define Day Objects-only experiment scope"
```

Expected: one commit containing only the executable verifier.

### Task 3: Transplant the Final Day Objects Implementation Without Its Ancestors

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectsView.swift`
- Create: `StepsTrader/Experiments/ExperimentalLabRoute.swift`
- Create: `StepsTrader/Utilities/ExperimentalFeatures.swift`
- Create: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Create: `StepsTrader/Metal/DayObjectsMeshGradientShader.metal`
- Create: `StepsTrader/Metal/DayObjectsPostShader.metal`
- Create: `Steps4Tests/DayObjectChoreographyTests.swift`
- Create: `Steps4Tests/DayObjectPaletteTests.swift`
- Create: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Create: `Steps4Tests/DayObjectSceneTests.swift`
- Create: `Steps4UITests/DayObjectsLabUITests.swift`
- Modify: `StepsTrader/StepsTraderApp.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Modify: `StepsTrader/Models/GradientPalette.swift`
- Modify: `StepsTrader/Localizable.xcstrings`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Create: `docs/superpowers/specs/2026-08-20-day-objects-choreography-design.md`
- Create: `docs/superpowers/plans/2026-08-20-day-objects-choreography.md`

**Interfaces:**
- Consumes: final committed snapshot `d9141cdce8d7b332f5748fc88134260c4091cc9e`, clean Canvas UI types, `GradientPalette`
- Produces: `ExperimentalLabRoute.dayObjects`, `ExperimentalFeatures.dayObjectsLab`, `GradientPalette.colorHexes`, the final Day Objects renderer and its test targets

- [ ] **Step 1: Restore only the final Day Objects-owned files**

Run this explicit mechanical transplant; do not restore a directory outside the listed Day Objects paths:

```bash
git restore --source=d9141cdce8d7b332f5748fc88134260c4091cc9e -- \
  StepsTrader/Experiments/DayObjects \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  StepsTrader/Metal/DayObjectsMeshGradientShader.metal \
  StepsTrader/Metal/DayObjectsPostShader.metal \
  Steps4Tests/DayObjectChoreographyTests.swift \
  Steps4Tests/DayObjectPaletteTests.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift \
  Steps4Tests/DayObjectSceneTests.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  docs/superpowers/specs/2026-08-20-day-objects-choreography-design.md \
  docs/superpowers/plans/2026-08-20-day-objects-choreography.md
```

Expected: only the listed paths become added. `.superpowers/` and every obsolete experiment directory remain absent.

- [ ] **Step 2: Create the single experiment flag**

Create `StepsTrader/Utilities/ExperimentalFeatures.swift` with exactly:

```swift
enum ExperimentalFeatures {
    #if DEBUG || INTERNAL_BUILD
    static let dayObjectsLab = true
    #else
    static let dayObjectsLab = false
    #endif
}
```

- [ ] **Step 3: Create the single Debug launch route**

Create `StepsTrader/Experiments/ExperimentalLabRoute.swift` with exactly:

```swift
#if DEBUG
import SwiftUI

enum ExperimentalLabRoute: String, CaseIterable {
    case dayObjects

    static var current: ExperimentalLabRoute? {
        if let name = UserDefaults.standard.string(forKey: "uiLab"),
           let route = ExperimentalLabRoute(rawValue: name),
           route.isEnabled {
            return route
        }

        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiLab"),
              index + 1 < arguments.count,
              let route = ExperimentalLabRoute(rawValue: arguments[index + 1]),
              route.isEnabled else {
            return nil
        }
        return route
    }

    private var isEnabled: Bool {
        ExperimentalFeatures.dayObjectsLab
    }

    @ViewBuilder
    var view: some View {
        DayObjectsLabView()
    }
}
#endif
```

This makes `dayRays`, `atmosphere`, `generativeScene`, and `formulaLab` fail enum parsing and fall through to the normal app.

- [ ] **Step 4: Add the Day Objects launch hook without changing Release behavior**

Apply only the already-reviewed `StepsTraderApp.swift` extraction from the omitted bench commit, then rename its route example:

```bash
git diff 2d2f679e1aa7d26c12c507894d5027815147491e^ \
  2d2f679e1aa7d26c12c507894d5027815147491e \
  -- StepsTrader/StepsTraderApp.swift > /tmp/day-objects-app-root.patch
git apply --3way /tmp/day-objects-app-root.patch
```

Change only the added comment from:

```swift
// Debug-only shortcut: `-uiLab dayRays` opens an experiment
```

to:

```swift
// Debug-only shortcut: `-uiLab dayObjects` opens the retained experiment
```

Verify the move was a pure extraction:

```bash
git diff --word-diff=porcelain -- StepsTrader/StepsTraderApp.swift
```

Expected changes: the Debug conditional router, the `appBody` property boundary, two moved closing braces, and the updated comment. No statement inside the production `GlassShimmerProvider` / `ZStack` tree changes.

- [ ] **Step 5: Expose Day Objects as the sole Appearance lab**

In `manualGroup` in `StepsTrader/Views/Settings/SettingsAppearancePage.swift`, add exactly one gated row after `textureSection`:

```swift
if ExperimentalFeatures.dayObjectsLab {
    dayObjectsLabSection
}
```

Add this property before `canvasShapesSection`:

```swift
private var dayObjectsLabSection: some View {
    NavigationLink {
        DayObjectsLabView()
    } label: {
        HStack(spacing: 12) {
            Image(systemName: "circle.grid.cross")
            VStack(alignment: .leading, spacing: 2) {
                Text("Day Objects")
                Text("Daily choreography with live motion and focus controls")
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 6: Add the four canonical colors consumed by Day Objects**

Add this property after `GradientPalette.colors` in `StepsTrader/Models/GradientPalette.swift`:

```swift
var colorHexes: [String] {
    switch self {
    case .warmSunset: ["#FFBF65", "#FD8973", "#003A6C", "#002646"]
    case .ocean:      ["#7FDBDA", "#3A9FBF", "#1A4B6E", "#0B1E33"]
    case .aurora:     ["#C4B5FD", "#7C6FBF", "#1F6E5C", "#0F1B2D"]
    case .dusk:       ["#EEDDC9", "#C0AC98", "#5E7282", "#384856"]
    case .dawn:       ["#EBBFC8", "#B87A92", "#4A3568", "#181430"]
    case .ember:      ["#F07838", "#D04428", "#2E1858", "#0C0A22"]
    case .horizon:    ["#D0A440", "#2898A8", "#105868", "#0A2832"]
    }
}
```

- [ ] **Step 7: Add only the committed Day Objects localization keys**

Add these keys to the top-level `strings` object in `StepsTrader/Localizable.xcstrings`, preserving JSON ordering and syntax:

```json
"Daily choreography with live motion and focus controls" : {
  "comment" : "Debug appearance settings – Day Objects lab description"
},
"Day Objects" : {
  "comment" : "Day Objects experimental lab title"
},
"Day Objects canvas" : {
  "comment" : "Accessibility label for the Day Objects rendered canvas"
},
"Day Objects grid" : {
  "comment" : "Accessibility label for the static Day Objects contact sheet"
},
"Focus" : {
  "comment" : "Day Objects lab control for visual clarity"
},
"Grid" : {
  "comment" : "Day Objects lab button that shows the contact sheet"
},
"Hide controls" : {
  "comment" : "Day Objects lab accessibility label"
},
"Motion" : {
  "comment" : "Day Objects lab control for choreography energy"
},
"Next 15" : {
  "comment" : "Day Objects lab button that advances the contact sheet"
},
"Next day" : {
  "comment" : "Day Objects lab button that advances its deterministic day fixture"
},
"Show controls" : {
  "comment" : "Day Objects lab accessibility label"
},
"Single" : {
  "comment" : "Day Objects lab button that returns to one canvas"
}
```

Do not copy the dirty `Localizable.xcstrings` from the old Day Objects worktree; that uncommitted file also contains unrelated Feeds, Me, and Canvas localization churn.

- [ ] **Step 8: Register only Day Objects, its route, and its flag in Xcode**

Edit `Steps4.xcodeproj/project.pbxproj` with the exact object IDs already used by the source snapshot:

```text
A16C80010000000000000001  ExperimentalFeatures.swift file reference
A16C90010000000000000001  ExperimentalFeatures.swift app Sources entry
9E5C000100000000000000D1  ExperimentalLabRoute.swift file reference
9E5C000200000000000000D1  ExperimentalLabRoute.swift app Sources entry
D0B100000000000000000001...D0B10000000000000000000A  Day Objects test refs/build entries
D0B100000000000000000011...D0B10000000000000000001D  Day Objects source/shader refs
D0B100000000000000000021...D0B10000000000000000002E  Day Objects app build entries
D0B10000000000000000002F  DayObjectsLabView.swift file reference
D0B100000000000000000031  Experiments/DayObjects PBXGroup
```

The `D0B...031` group must contain these ten Swift files in this order:

```text
DayObjectComposition.swift
DayObjectPalette.swift
DayObjectChoreography.swift
DayObjectRenderFrame.swift
DayObjectsRenderer.swift
DayObjectsMetalView.swift
DayObjectsView.swift
DayObjectsLabView.swift
DayObjectTypes.swift
DayObjectScene.swift
```

Add the three shader refs to the existing `Metal` group, the four unit-test refs to `Steps4Tests`, the UI-test ref to `Steps4UITests`, and the corresponding build IDs to their Sources phases. Add `ExperimentalFeatures.swift` to the existing `Utilities` group and `ExperimentalLabRoute.swift` plus `D0B...031` directly to the `StepsTrader` group.

After editing, run:

```bash
test "$(rg -c 'D0B1000000000000000000' Steps4.xcodeproj/project.pbxproj)" -ge 20
test -z "$(rg -n 'RichCanvas|GenerativeScene|CanvasAtmosphere|DayRays|FormulaLab' Steps4.xcodeproj/project.pbxproj || true)"
plutil -lint StepsTrader/Localizable.xcstrings
```

Expected: both tests exit zero and `plutil` reports `OK`.

- [ ] **Step 9: Run the scope verifier and inspect the complete staged surface**

Run:

```bash
Scripts/verify-experiment-scope.sh
git status --short
git diff --check
git diff --stat codex/canvas-ui-clean...HEAD
```

Expected: `Day Objects is the only tracked experiment.` No `.superpowers/`, obsolete experiment path, or unlisted artifact appears.

- [ ] **Step 10: Commit the retained experiment**

Stage only these confirmed paths:

```bash
git add -- \
  Steps4.xcodeproj/project.pbxproj \
  Steps4Tests/DayObjectChoreographyTests.swift \
  Steps4Tests/DayObjectPaletteTests.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift \
  Steps4Tests/DayObjectSceneTests.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  StepsTrader/Experiments/DayObjects \
  StepsTrader/Experiments/ExperimentalLabRoute.swift \
  StepsTrader/Localizable.xcstrings \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  StepsTrader/Metal/DayObjectsMeshGradientShader.metal \
  StepsTrader/Metal/DayObjectsPostShader.metal \
  StepsTrader/Models/GradientPalette.swift \
  StepsTrader/StepsTraderApp.swift \
  StepsTrader/Utilities/ExperimentalFeatures.swift \
  StepsTrader/Views/Settings/SettingsAppearancePage.swift \
  docs/superpowers/specs/2026-08-20-day-objects-choreography-design.md \
  docs/superpowers/plans/2026-08-20-day-objects-choreography.md
git diff --cached --check
git commit -m "feat: keep Day Objects as the sole canvas experiment"
```

Expected: the commit contains only the listed Day Objects and integration paths.

### Task 4: Verify the Clean Day Objects Branch

**Files:**
- Test: `Scripts/verify-experiment-scope.sh`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4UITests/DayObjectsLabUITests.swift`

**Interfaces:**
- Consumes: completed `codex/day-objects-clean`
- Produces: verified clean head safe to publish and use as the preview base

- [ ] **Step 1: Run the structural scope gate**

Run:

```bash
Scripts/verify-experiment-scope.sh
test -z "$(git status --porcelain)"
git diff --check codex/canvas-ui-clean...HEAD
```

Expected: scope message, clean worktree, and no whitespace errors.

- [ ] **Step 2: Run all Day Objects unit tests**

Run:

```bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Run the Day Objects launch UI test**

Run:

```bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:Steps4UITests/DayObjectsLabUITests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `** TEST SUCCEEDED **`; the launch argument opens the Day Objects controls and grid.

- [ ] **Step 4: Run the complete unit baseline**

Run:

```bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:Steps4Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: zero failures; the baseline allows the same one pre-existing skipped test.

- [ ] **Step 5: Build the ordinary preview scheme**

Run:

```bash
xcodebuild build \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `** BUILD SUCCEEDED **`.

### Task 5: Publish the Clean Stack and Update GitHub PRs

**Files:**
- No source changes

**Interfaces:**
- Consumes: verified `codex/canvas-ui-clean`, verified `codex/day-objects-clean`, existing PR #18
- Produces: PR #18 based on `main`, remote `codex/day-objects-clean`, and a new draft Day Objects PR

- [ ] **Step 1: Fetch and verify the force-with-lease expectation**

Run:

```bash
git fetch origin
test "$(git rev-parse origin/feat/canvas-ui-simplification)" = 828e2b5a66b7ed368bcf942b11b53d94f3c614b5
git log --oneline main..codex/canvas-ui-clean
```

Expected: remote head is still the reviewed PR #18 SHA. If it differs, stop publication and inspect the new remote commits instead of weakening the lease.

- [ ] **Step 2: Replace the remote PR #18 head with the verified clean Canvas history**

Run:

```bash
git push \
  --force-with-lease=refs/heads/feat/canvas-ui-simplification:828e2b5a66b7ed368bcf942b11b53d94f3c614b5 \
  origin codex/canvas-ui-clean:feat/canvas-ui-simplification
gh pr edit 18 --repo Pudan416/step-trader --base main
```

Expected: push succeeds under the pinned lease and PR #18 reports `main` as its base.

- [ ] **Step 3: Verify PR #18 contains no experiment code**

Run:

```bash
gh pr view 18 --repo Pudan416/step-trader --json baseRefName,headRefName,url,files,commits
```

Expected: base `main`, head `feat/canvas-ui-simplification`, no path under `StepsTrader/Experiments/`, and no obsolete experiment plan/spec.

- [ ] **Step 4: Push Day Objects and create its stacked draft PR**

Run:

```bash
git push -u origin codex/day-objects-clean
gh pr create \
  --repo Pudan416/step-trader \
  --draft \
  --base feat/canvas-ui-simplification \
  --head codex/day-objects-clean \
  --title "feat: keep Day Objects as the sole canvas experiment" \
  --body $'## Summary\n- retain the final Day Objects choreography and Metal renderer\n- remove every other experiment from the active branch topology\n- keep one debug launch route and one Appearance lab entry\n\n## Verification\n- Scripts/verify-experiment-scope.sh\n- Day Objects unit and UI tests\n- complete Steps4Tests suite\n- Debug simulator build'
```

Expected: GitHub returns one new draft PR URL.

- [ ] **Step 5: Inspect both PRs and their checks**

Run:

```bash
gh pr checks 18 --repo Pudan416/step-trader --watch
gh pr view codex/day-objects-clean --repo Pudan416/step-trader --json url,isDraft,baseRefName,headRefName,files,statusCheckRollup
```

Expected: PR #18 checks pass; the Day Objects PR is draft, based on `feat/canvas-ui-simplification`, and lists no obsolete experiment file.

### Task 6: Publish the Single Preview Branch

**Files:**
- No source changes

**Interfaces:**
- Consumes: `codex/day-objects-clean`, which already contains clean Canvas UI plus Day Objects
- Produces: remote `preview/all-current`, runnable with the ordinary `Steps4` scheme

- [ ] **Step 1: Point the preview branch at the verified integration head**

Run:

```bash
git branch preview/all-current codex/day-objects-clean
git push -u origin preview/all-current
```

Expected: remote branch is created without a PR.

- [ ] **Step 2: Verify preview content and buildability**

Run:

```bash
test "$(git rev-parse preview/all-current)" = "$(git rev-parse codex/day-objects-clean)"
git grep -n 'case dayObjects' preview/all-current -- StepsTrader/Experiments/ExperimentalLabRoute.swift
git grep -n -E 'RichCanvas|RichFigure|RichRender|GenerativeScene|CanvasAtmosphere|DayRays|FormulaLab' preview/all-current -- StepsTrader Steps4Tests Steps4UITests Steps4.xcodeproj && exit 1 || true
```

Expected: one `case dayObjects` line and no obsolete symbol output.

### Task 7: Retire Obsolete Experiment Worktrees and Branches

**Files:**
- Backup outside tracked worktree: `.git/codex-backups/2026-08-22/formula-lab-uncommitted.patch`
- Backup outside tracked worktree: `.git/codex-backups/2026-08-22/day-objects-localization.patch`

**Interfaces:**
- Consumes: published clean PRs, passing checks, working preview branch
- Produces: fewer worktrees and branches while preserving the dirty primary checkout and recoverable uncommitted patches

- [ ] **Step 1: Capture the two obsolete worktree diffs without staging them**

Run from the repository root:

```bash
backup_dir="$(git rev-parse --git-common-dir)/codex-backups/2026-08-22"
mkdir -p "$backup_dir"
git -C '.claude/worktrees/codex-ai-formula-lab' diff --binary > "$backup_dir/formula-lab-uncommitted.patch"
git -C '.worktrees/day-objects-choreography' diff --binary > "$backup_dir/day-objects-localization.patch"
test -s "$backup_dir/formula-lab-uncommitted.patch"
test -s "$backup_dir/day-objects-localization.patch"
```

Expected: two non-empty ignored backup patches. The Day Objects localization patch is not applied to the clean branch because it mixes unrelated app changes.

- [ ] **Step 2: Confirm GitHub no longer depends on `codex/remove-stipple`**

Run:

```bash
test "$(gh pr view 18 --repo Pudan416/step-trader --json baseRefName --jq .baseRefName)" = main
gh pr list --repo Pudan416/step-trader --state open --json baseRefName,headRefName --jq '.[] | select(.baseRefName == "codex/remove-stipple" or .headRefName == "codex/remove-stipple")'
```

Expected: second command prints nothing.

- [ ] **Step 3: Remove obsolete linked worktrees**

Run:

```bash
git worktree remove --force '.claude/worktrees/charming-hellman-e73c78'
git worktree remove --force '.claude/worktrees/codex-ai-formula-lab'
git worktree remove --force '.worktrees/day-objects-choreography'
git worktree prune
```

Expected: `git worktree list` no longer lists the two Formula Lab worktrees or the old Day Objects worktree. Their committed tips still exist in private safety refs, and their uncommitted diffs exist in `.git/codex-backups/2026-08-22/`.

- [ ] **Step 4: Delete obsolete local and remote experiment branches**

Run:

```bash
git branch -D claude/charming-hellman-e73c78
git branch -D codex/ai-formula-lab
git branch -D codex/day-objects-choreography
git branch -D codex/remove-stipple
git push origin --delete codex/remove-stipple
```

Expected: the four obsolete local branches and the obsolete remote base disappear. Do not delete the dirty primary checkout's local `feat/canvas-ui-simplification` branch in this task.

- [ ] **Step 5: Remove private committed safety refs after all published checks pass**

Run:

```bash
git update-ref -d refs/codex-backup/2026-08-22/pr18
git update-ref -d refs/codex-backup/2026-08-22/remove-stipple
git update-ref -d refs/codex-backup/2026-08-22/formula-lab
git update-ref -d refs/codex-backup/2026-08-22/day-objects
test -z "$(git for-each-ref --format='%(refname)' refs/codex-backup/2026-08-22/)"
```

Expected: no private committed experiment ref remains. The two uncommitted patch backups remain recoverable until the broader dirty-worktree split is complete.

- [ ] **Step 6: Report the final human-facing topology**

Run:

```bash
git worktree list
git branch -vv
gh pr list --repo Pudan416/step-trader --state open --json number,title,baseRefName,headRefName,isDraft,url
```

Expected active experiment topology:

```text
main
└─ feat/canvas-ui-simplification       PR #18
   └─ codex/day-objects-clean          draft PR
      └─ preview/all-current           preview only
```

The primary dirty checkout is explicitly reported as preserved for the next phase that separates Me, Feeds, typography, canvas-fill, and production rendering PRs.

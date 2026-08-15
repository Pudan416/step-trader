# Rendering Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop unnecessary animation work, bound expensive procedural rendering, and clean rebuildable repository artifacts while preserving current behavior.

**Architecture:** A tab-scoped environment value and pure playback policy control continuous rendering. A pure render-budget policy controls expensive shape detail. Overlay selection exposes testable resource requirements, and cleanup removes only verified generated or unused content.

**Tech Stack:** Swift 5, SwiftUI Canvas/TimelineView, MetalKit, XCTest, Node.js/npm, Git.

**Spec:** `docs/superpowers/specs/2026-08-15-rendering-performance-design.md`

## Global Constraints

- Main app deployment target remains iOS 17.
- Preserve all existing uncommitted user changes.
- Do not change persisted canvas, HealthKit, localization, or Supabase contracts.
- Do not rewrite Git history, push, merge, or publish.
- New behavior must follow RED→GREEN TDD.
- Cleanup deletes only content recoverable from Git or package/build commands.

---

### Task 1: Rendering activity policy and tab lifecycle

**Files:**
- Create: `StepsTrader/Utilities/RenderingActivity.swift`
- Create: `Steps4Tests/RenderingActivityTests.swift`
- Modify: `StepsTrader/Views/MainTabView.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Modify: `StepsTrader/Views/GenerativeCanvasView.swift`
- Modify: `StepsTrader/Views/Components/EnergyGradientBackground.swift`
- Modify: `StepsTrader/Utilities/GlassCardModifier.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj` if explicit source membership is required

**Interfaces:**
- Produces `EnvironmentValues.renderingIsActive: Bool`.
- Produces `RenderingActivity.shouldAnimate(isViewActive:sceneIsActive:reduceMotion:) -> Bool`.
- `GenerativeCanvasView` consumes an active state without changing persisted data.

- [ ] Write unit tests proving selected/active animates and hidden, background, or Reduce Motion states do not.
- [ ] Run the focused tests and confirm RED because the policy does not exist.
- [ ] Implement the environment value and pure policy.
- [ ] Set the value independently on all three `TabView` pages.
- [ ] Pause Canvas, animated gradient, and shimmer schedules using the policy.
- [ ] Run focused and related tests and confirm GREEN.

### Task 2: Overlay resource routing

**Files:**
- Modify: `StepsTrader/Models/CanvasOverlayStyle.swift`
- Modify: `StepsTrader/Views/Components/CanvasAnimationOverlay.swift`
- Create or modify: `Steps4Tests/CanvasOverlayStyleTests.swift`

**Interfaces:**
- Produces testable overlay resource classification used by the router.
- `.none` produces no Metal-backed view and does not intercept touches.

- [ ] Write tests proving only `.smudge` requires the smudge renderer and only `.cosmic` requires the cosmic renderer.
- [ ] Run the focused tests and confirm RED.
- [ ] Implement the classification and route `.none` to a non-interactive empty view.
- [ ] Run focused tests and confirm GREEN.

### Task 3: Adaptive procedural-render budget

**Files:**
- Create: `StepsTrader/Shapes/CanvasRenderBudget.swift`
- Create: `Steps4Tests/CanvasRenderBudgetTests.swift`
- Modify: `StepsTrader/Shapes/SnowflakeShapeRenderer.swift`
- Modify: `StepsTrader/Shapes/OrganicBlobShapeRenderer.swift`
- Modify: `StepsTrader/Views/GenerativeCanvasView.swift`
- Modify: `StepsTrader/Views/Palette/HappeningLiquidField.swift`
- Modify: `StepsTrader/Shapes/MetaballGenerator.swift` only if required by the selected policy
- Modify: `Steps4.xcodeproj/project.pbxproj` if explicit source membership is required

**Interfaces:**
- Produces pure budget decisions for trail samples, organic layers, and metaball grid resolution.
- Renderers consume budgets without modifying model serialization.

- [ ] Write table-driven tests for normal, crowded, and Low Power Mode budgets.
- [ ] Run the focused tests and confirm RED.
- [ ] Implement the smallest budget policy satisfying the tests.
- [ ] Pass budget values into snowflake, organic-blob, and liquid render paths.
- [ ] Preserve existing geometry/layout characterization tests.
- [ ] Run focused renderer and layout tests and confirm GREEN.

### Task 4: AppModel invalidation hygiene

**Files:**
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`
- Modify: `StepsTrader/AppModel.swift` only where duplicate notification can be proven
- Modify: existing AppModel/energy tests or create a focused regression test

**Interfaces:**
- Preserve all existing energy values, widget updates, and sync calls.
- Remove only redundant manual invalidation; store forwarding remains unless a test proves a safe narrower boundary.

- [ ] Add a regression test around observable energy state if one can exercise the duplicate notification reliably.
- [ ] Confirm RED for an observable duplicate; otherwise record that only the explicit redundant send is safely removable.
- [ ] Remove the redundant explicit `objectWillChange.send()` from energy recalculation while preserving the user’s activity-install change.
- [ ] Run energy, HealthKit, and widget tests.

### Task 5: Repository cleanup

**Files:**
- Modify: `.gitignore`
- Remove from Git index: `tg-admin/node_modules/**`
- Remove: `StepsTrader/Fonts/**`
- Remove generated local artifacts: `build/`, `admin-panel/.next/`, `admin-panel/tsconfig.tsbuildinfo`, `.DS_Store`, Xcode `xcuserdata`, `OnboardingPreview/.swiftpm/`

**Interfaces:**
- `npm --prefix tg-admin ci` remains the reproducible dependency restore path.
- Xcode target continues to build without the unused font files.

- [ ] Verify every deletion is ignored/generated or absent from Xcode build resources.
- [ ] Add a scoped `tg-admin/.gitignore` and correct the overbroad `docs/` ignore rule.
- [ ] Remove tracked dependencies from the index and unused tracked fonts.
- [ ] Remove rebuildable local artifacts after tests no longer need them.
- [ ] Verify Git status contains no accidental secret or user-file deletion.

### Task 6: Integration, regression suite, and performance evidence

**Files:**
- Modify only files required by failures attributable to Tasks 1–5.

**Interfaces:**
- Produces a buildable repository and evidence report; no external publication.

- [ ] Run focused rendering tests.
- [ ] Run all 366+ iOS unit tests.
- [ ] Run a Debug simulator build.
- [ ] Run admin ESLint and `tg-admin` TypeScript typecheck.
- [ ] Run `git diff --check` and inspect the complete diff.
- [ ] Record a fresh bounded Time Profiler launch and compare application hotspots with the baseline.
- [ ] Attempt the UI suite with a bounded timeout and report its exact result.

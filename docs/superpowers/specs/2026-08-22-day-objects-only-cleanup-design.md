# Day Objects Only Experiment Cleanup Design

## Goal

Keep Day Objects as the only experimental canvas laboratory, remove the other
experiment families from the active code and branch topology, and rebuild a
single previewable app without losing the unrelated Canvas UI, Me, or Feeds
work.

## Current State

The repository's `main` branch does not contain the recent experiment stack.
The obsolete experiments live in local or remote feature branches derived from
`codex/remove-stipple`:

- `RichCanvas` is carried by `codex/remove-stipple` and every descendant.
- `GenerativeScene`, `Atmosphere`, and `DayRays` were introduced by the visual
  experiment bench commit in the Canvas UI branch.
- Formula Lab lives in the `claude/charming-hellman-e73c78` and
  `codex/ai-formula-lab` branches.
- The final Day Objects implementation lives at the tip of
  `codex/day-objects-choreography`, but its history also contains all the
  obsolete experiment ancestors.
- PR #18 currently targets `codex/remove-stipple`, so its visible diff is clean
  only while that obsolete base continues to exist.

Because the unwanted code is not on `main`, merging the old branches and then
adding deletion commits would preserve unnecessary code and history. The clean
result must instead be reconstructed from `main` with only the wanted commits
and files.

## Kept Product and Experiment Scope

The following stays:

- The production Canvas implementation, including
  `StepsTrader/Views/GenerativeCanvasView.swift` and the normal Canvas tab.
- The Canvas UI simplification behavior that is currently represented by PR
  #18, after removing its dependency on the Rich Canvas branch.
- The production-only removal of the stipple texture from commit `23e8d31e`.
  No later Rich Canvas laboratory commit is retained with it.
- The final Day Objects implementation from
  `codex/day-objects-choreography`, including its model, renderer, views,
  controls, tests, and static Metal shaders.
- The unrelated Me, Feeds, typography, canvas-fill, and production rendering
  changes currently present as uncommitted work. They will be split into later
  PRs after this cleanup establishes a clean base.

Day Objects will be the only debug experiment exposed by the app. Its settings
entry and `-uiLab dayObjects` launch route remain available in Debug or Internal
builds.

## Removed Scope

The reconstructed branches must contain none of the following experiment
families:

- `StepsTrader/Experiments/RichCanvas/`
- `StepsTrader/Experiments/GenerativeScene/`
- `StepsTrader/Experiments/Atmosphere/`
- `StepsTrader/Experiments/DayRays/`
- `StepsTrader/Experiments/FormulaLab/`

Their dedicated tests, fixtures, static Metal shaders, Xcode project entries,
settings links, launch routes, feature flags, plans, specs, handoff notes, and
generated review artifacts are also excluded. In particular, the cleaned
project must not reference `RichCanvas`, `GenerativeScene`, `CanvasAtmosphere`,
`DayRays`, or `FormulaLab` symbols.

The production `GenerativeCanvasView.swift` is explicitly not part of this
deletion. Name similarity to `GenerativeScene` must not be used as a reason to
remove or rewrite it.

## Branch Reconstruction

Work happens in the isolated `codex/experiment-cleanup` worktree. The dirty
primary checkout and every old worktree remain untouched until replacement
branches have passed verification.

The clean branch chain will be:

```text
main
└─ cleaned Canvas UI branch (updated PR #18)
   └─ cleaned Day Objects branch (new draft PR)
      └─ preview/all-current (preview branch, not a production PR)
```

The Canvas UI branch is rebuilt from `main` by applying only production Canvas
and Canvas UI commits. The Rich Canvas implementation commits and the visual
experiment bench commit are omitted. If a selected Canvas UI commit has a
textual dependency on an omitted experiment, the dependency is removed during
the transplant rather than restored.

PR #18 keeps its existing purpose and review conversation, but its base changes
to `main` and its head is updated to the verified clean history. The remote head
must not be force-updated until a local safety ref points to the old head and
the reconstructed branch has passed its scoped tests.

The Day Objects branch is then rebuilt on the clean Canvas UI head. Only the Day
Objects design, implementation, tests, project entries, and shaders are
transplanted. Shared experiment routing is recreated with a single Day Objects
case instead of copying the four-lab bench infrastructure.

Formula Lab receives no replacement branch or PR. The Rich Canvas,
GenerativeScene, Atmosphere, and DayRays branches likewise receive no new PR.

## App Surface

The ordinary `Steps4` Xcode scheme remains the only scheme needed for preview.
The app launches into its normal product flow, where Canvas, Feeds, and Me show
their current integrated behavior. Settings > Appearance contains one
experimental destination: Day Objects.

The debug launch router accepts only `dayObjects`. Unsupported old route names
fall through to the normal app instead of resolving to dead views.

The later `preview/all-current` branch will merge or rebuild the heads of the
clean feature PRs. Conflict-only edits stay on that preview branch and are not
silently copied back into review PRs.

## Safety and Repository Hygiene

Before changing published history, local safety refs preserve the exact tips
of PR #18 and every source branch used for reconstruction. These refs remain
local and are removed only after the replacement branches are pushed, GitHub
shows the expected diffs, and the app builds from the preview branch.

Ignored secrets, `xcuserdata`, `.impeccable`, `.superpowers` execution reports,
simulator captures, and generated image artifacts are never staged. Files are
staged by explicit path only.

Old worktrees and obsolete local or remote branches are removed only after:

1. The clean Canvas UI and Day Objects branches are published.
2. PR diffs contain no obsolete experiment files or symbols.
3. Required tests pass on both branches.
4. The single preview app builds and exposes Day Objects.

Remote branch deletion is the final cleanup step. It must not precede retargeting
PR #18 away from `codex/remove-stipple`.

## Verification

The cleanup is accepted when all of the following are true:

- `rg` finds no obsolete experiment symbols or filenames in tracked source,
  test, shader, and Xcode project files on the cleaned Day Objects branch.
- `StepsTrader/Views/GenerativeCanvasView.swift` remains tracked and compiles.
- The Xcode project references the Day Objects files and shaders, and references
  none of the removed experiment files.
- The Debug/Internal Appearance page exposes Day Objects and no other lab.
- `-uiLab dayObjects` opens the Day Objects lab; each former route name launches
  the normal app.
- Canvas UI unit and UI-test targets selected for PR #18 pass.
- All Day Objects unit tests pass.
- The complete `Steps4Tests` unit suite passes on the final cleaned branch.
- A Debug simulator build of the `Steps4` scheme succeeds.
- GitHub shows PR #18 based on `main` and a separate draft Day Objects PR based
  on the cleaned Canvas UI head.

The clean `main` baseline for this work executed 582 unit tests with zero
failures and one pre-existing skipped test on an iPhone 17 simulator running
iOS 26.3.1.

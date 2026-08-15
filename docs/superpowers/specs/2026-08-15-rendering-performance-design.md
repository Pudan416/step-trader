# Rendering Performance Design

## Goal

Reduce idle and interactive rendering work in the iOS app without changing the visual language, stored canvas format, HealthKit behavior, or Supabase contracts.

## Scope

- Pause continuous rendering when a tab is not selected, the scene is not active, or Reduce Motion requests a static presentation.
- Ensure the disabled canvas overlay does not allocate Metal resources or intercept input.
- Bound the cost of snowflake trails, organic blobs, and liquid metaballs while preserving their recognizable appearance.
- Remove redundant broad `AppModel` invalidation where published stores already notify observers.
- Remove confirmed generated/rebuildable repository clutter and stop tracking `tg-admin/node_modules`.
- Add behavioral tests for rendering policies and keep existing visual/layout characterization tests passing.

## Architecture

`MainTabView` publishes a lightweight render-activity environment value per tab. Renderers combine that value with `scenePhase` and accessibility settings through pure policy functions. Timeline schedules use the resulting boolean as their `paused` input, and static fallbacks keep the latest visible frame.

Shape complexity is selected by a small pure `CanvasRenderBudget` policy from element/source counts and Low Power Mode. Renderers consume the budget; the data model and persisted canvas schema remain unchanged.

Overlay routing is expressed as model behavior on `CanvasOverlayStyle`, making `.none`, `.smudge`, and `.cosmic` testable without instantiating SwiftUI or Metal views.

## Constraints

- Minimum supported version of the main app remains iOS 17.
- No changes to Supabase schemas, migration history, HealthKit identifiers, localization behavior, or stored canvas JSON.
- Existing uncommitted user changes in Gallery, activity suggestions, happenings, localization, and tests must be preserved.
- Do not rewrite Git history, push, merge, or publish.
- Repository cleanup may delete only generated/rebuildable files and tracked assets confirmed unused by the Xcode target.
- Performance claims require build/test evidence and a fresh Time Profiler comparison; exact FPS still requires a physical device.

## Testing

- Unit tests cover activity decisions, overlay routing, and adaptive render budgets.
- Existing ray, metaball, layout, HealthKit, and full unit suites remain green.
- Admin ESLint and `tg-admin` TypeScript checks remain green.
- A Debug simulator build and a bounded Time Profiler launch verify integration and compare hotspots.

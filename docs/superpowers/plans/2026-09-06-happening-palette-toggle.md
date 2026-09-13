# Persistent Happening Palette Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Canvas happening palette into a persistent ten-slot editor with exact Metal previews, two-activation add/remove, explicit added status, and smooth physical-device performance.

**Architecture:** `GalleryView` owns one pure interaction state and one cached assignment snapshot. The existing `DayObjectsMetalView` switches between Canvas and palette presentation modes; a palette frame builder supplies ten fixed actors to the same renderer, while SwiftUI supplies only labels, badges, hit targets, instructions, and list-management panels. Add and remove use symmetric MainActor transactions so `DayCanvas`, daily energy entries, and sync state cannot diverge on a failed local save.

**Tech Stack:** Swift 6, SwiftUI, UIKit accessibility APIs, Metal/MetalKit, XCTest/XCUITest, existing `DayObjects` renderer and persistence services.

**Spec:** `docs/superpowers/specs/2026-09-06-happening-palette-toggle-design.md`

## Global Constraints

- The palette always shows exactly the configured ten happenings in the existing `3–2–3–2` layout; add/remove never deletes or reflows a slot.
- Available slots share one neutral translucent yellow sphere material; exact production shape, material, and colour appear only in addition preview.
- First activation arms add or remove; second activation of the same slot performs it; activating another slot switches the armed intent.
- Added slots retain the committed silhouette, use strong desaturation, and show a liquid-glass check badge; removal preview replaces check with minus and adds a restrained warm edge.
- Energy bar stays visible, main tab bar stays hidden, list stays bottom-left, and plus/close stays bottom-right.
- Use the existing `DayObjectsMetalView`; do not add a second Metal view or per-slot SwiftUI material renderer.
- Production labels keep the 15-character limit, one fixed font size, and at most two lines.
- Visible instructions are localized in Russian and English; VoiceOver says “activate again,” never “double tap,” for the app-level second activation.
- Respect Reduce Motion by using a short opacity crossfade rather than geometric morph/lift/pulse.
- Interactive transitions target measured 60 fps; settled palette rendering returns to 30 fps or a static frame.
- Before editing, inspect and preserve the current uncommitted changes in `DayObjectsRenderer.swift`, `DayObjectPaletteSet.swift`, `DayObjectVisualLanguage.swift`, `DayObjectPaletteTests.swift`, `DayObjectRenderFrameTests.swift`, `Localizable.xcstrings`, and unrelated Me/audio artifacts. Stage and commit only files named by the current task.

---

### Task 1: Replace the consumptive palette state with a reversible interaction state machine

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningPaletteInteraction.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: create `Steps4Tests/HappeningPaletteInteractionTests.swift`

**Interfaces:**
- Consumes: the set of happening IDs currently represented by `DayCanvas.elements`.
- Produces: `HappeningPaletteInteractionState`, `HappeningPaletteMutation`, `HappeningPaletteTapDecision`, `HappeningPaletteSlotVisualState`, and `HappeningPaletteConfirmation` for the renderer and SwiftUI tasks.

- [ ] **Step 1: Add the production and test files to their existing Palette and Steps4Tests groups and Sources build phases**

Add file references for `HappeningPaletteInteraction.swift` beside `HappeningFieldPresentation.swift` and `HappeningPaletteInteractionTests.swift` beside `HappeningFieldLayoutTests.swift`. Add exactly one Sources entry for each target. Do not reorder unrelated project entries.

- [ ] **Step 2: Write failing reducer tests**

```swift
import XCTest
@testable import Steps4

final class HappeningPaletteInteractionTests: XCTestCase {
    func testAvailableNeedsTwoActivationsToAdd() {
        var state = HappeningPaletteInteractionState()
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .armed(.add("walk")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: []), .additionPreview)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
    }

    func testAddedNeedsTwoActivationsToRemove() {
        var state = HappeningPaletteInteractionState()
        let added: Set<String> = ["walk"]
        XCTAssertEqual(state.tap(id: "walk", addedIDs: added), .armed(.remove("walk")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: added), .removalPreview)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: added), .perform(.remove("walk")))
    }

    func testSwitchingSlotReplacesArmedIntentWithoutMutating() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: [])
        XCTAssertEqual(state.tap(id: "read", addedIDs: []), .armed(.add("read")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: []), .available)
        XCTAssertEqual(state.visualState(for: "read", addedIDs: []), .additionPreview)
    }

    func testFailedMutationStaysArmedAndSuccessfulMutationConfirms() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: [])
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
        state.resolve(.add("walk"), succeeded: false)
        XCTAssertEqual(state.armedMutation, .add("walk"))
        XCTAssertNil(state.pendingMutation)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
        state.resolve(.add("walk"), succeeded: true)
        XCTAssertNil(state.armedMutation)
        XCTAssertEqual(state.confirmation, .added("walk"))
    }

    func testCancelClearsArmedPendingAndConfirmation() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: [])
        state.cancel()
        XCTAssertEqual(state, HappeningPaletteInteractionState())
    }
}
```

- [ ] **Step 3: Run the reducer tests and verify the missing-type failure**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningPaletteInteractionTests
```

Expected: compilation fails because `HappeningPaletteInteractionState` and its related enums do not exist.

- [ ] **Step 4: Implement the pure state machine**

```swift
import Foundation

enum HappeningPaletteMutation: Equatable {
    case add(String)
    case remove(String)

    var id: String {
        switch self {
        case let .add(id), let .remove(id): id
        }
    }
}

enum HappeningPaletteTapDecision: Equatable {
    case armed(HappeningPaletteMutation)
    case perform(HappeningPaletteMutation)
    case ignored
}

enum HappeningPaletteSlotVisualState: Equatable {
    case available
    case additionPreview
    case added
    case removalPreview
}

enum HappeningPaletteConfirmation: Equatable {
    case added(String)
    case removed(String)
}

struct HappeningPaletteInteractionState: Equatable {
    private(set) var armedMutation: HappeningPaletteMutation?
    private(set) var pendingMutation: HappeningPaletteMutation?
    private(set) var confirmation: HappeningPaletteConfirmation?

    mutating func tap(id: String, addedIDs: Set<String>) -> HappeningPaletteTapDecision {
        guard pendingMutation == nil else { return .ignored }
        confirmation = nil
        let intended: HappeningPaletteMutation = addedIDs.contains(id) ? .remove(id) : .add(id)
        guard armedMutation == intended else {
            armedMutation = intended
            return .armed(intended)
        }
        pendingMutation = intended
        return .perform(intended)
    }

    mutating func resolve(_ mutation: HappeningPaletteMutation, succeeded: Bool) {
        guard pendingMutation == mutation else { return }
        pendingMutation = nil
        guard succeeded else { return }
        armedMutation = nil
        confirmation = switch mutation {
        case let .add(id): .added(id)
        case let .remove(id): .removed(id)
        }
    }

    mutating func clearConfirmation() { confirmation = nil }

    mutating func cancel() {
        armedMutation = nil
        pendingMutation = nil
        confirmation = nil
    }

    func visualState(for id: String, addedIDs: Set<String>) -> HappeningPaletteSlotVisualState {
        if armedMutation == .add(id) { return .additionPreview }
        if armedMutation == .remove(id) { return .removalPreview }
        return addedIDs.contains(id) ? .added : .available
    }
}
```

- [ ] **Step 5: Run the reducer tests and commit**

Run the Task 1 test command again. Expected: all `HappeningPaletteInteractionTests` pass.

```bash
git add Steps4.xcodeproj/project.pbxproj StepsTrader/Views/Palette/HappeningPaletteInteraction.swift Steps4Tests/HappeningPaletteInteractionTests.swift
git commit -m "feat: model reversible happening palette states"
```

---

### Task 2: Make add and remove symmetric durable transactions

**Files:**
- Modify: `StepsTrader/Views/Gallery/GalleryNotifications.swift`
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Test: `Steps4Tests/HappeningFieldLayoutTests.swift`
- Test: `Steps4Tests/HappeningAdditionsTests.swift`

**Interfaces:**
- Consumes: `HappeningPaletteMutation` from Task 1 and existing `CanvasHappeningSpawnTransaction`.
- Produces: `CanvasHappeningRemovalTransaction.commit(canvasLoaded:canvas:model:happeningID:at:persist:) -> CanvasHappeningRemovalResult?` and once-per-day usage semantics.

- [ ] **Step 1: Write failing removal transaction tests**

Add tests that construct one fixed `CanvasElement(optionId: "walk")` and assert:

```swift
let failed = CanvasHappeningRemovalTransaction.commit(
    canvasLoaded: true,
    canvas: canvas,
    model: model,
    happeningID: "walk",
    at: date,
    persist: { _ in false }
)
XCTAssertNil(failed)
XCTAssertEqual(canvas.elements.count, 1)
XCTAssertEqual(model.todayAdditions.map(\.optionId), ["walk"])
```

Then assert success returns an empty canonical Canvas and removes the matching `OptionEntry`, while a mismatched day key and missing happening return `nil` without side effects.

- [ ] **Step 2: Write a failing remove/re-add usage test**

```swift
func testRemoveAndReAddOnSameDayRecordsOneUse() throws {
    let model = makeModel()
    let date = Date(timeIntervalSince1970: 1_786_176_000)
    model.loadDailyEnergyState()
    let before = try XCTUnwrap(model.happeningStore.happening(id: "happening_walk")?.useCount)
    let first = try XCTUnwrap(model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date))
    model.removeAddition(entryId: first.id)
    XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date))
    XCTAssertEqual(model.happeningStore.happening(id: "happening_walk")?.useCount, before + 1)
}
```

- [ ] **Step 3: Run the focused tests and verify failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningFieldLayoutTests -only-testing:Steps4Tests/HappeningAdditionsTests
```

Expected: removal tests fail because the transaction is absent; usage test reports two increments.

- [ ] **Step 4: Implement the removal transaction**

Add to `GalleryNotifications.swift`:

```swift
struct CanvasHappeningRemovalResult {
    let canvas: DayCanvas
    let removedElement: CanvasElement
}

@MainActor
enum CanvasHappeningRemovalTransaction {
    static func commit(
        canvasLoaded: Bool,
        canvas: DayCanvas,
        model: AppModel,
        happeningID: String,
        at date: Date,
        persist: (DayCanvas) -> Bool
    ) -> CanvasHappeningRemovalResult? {
        let capturedDayKey = AppModel.dayKey(for: date)
        guard canvasLoaded, canvas.dayKey == capturedDayKey,
              let index = canvas.elements.firstIndex(where: { $0.optionId == happeningID })
        else { return nil }
        var canonical = canvas
        let removed = canonical.elements.remove(at: index)
        canonical.lastModified = date
        guard persist(canonical) else { return nil }
        model.removeAddition(entryId: removed.id.uuidString)
        return CanvasHappeningRemovalResult(canvas: canonical, removedElement: removed)
    }
}
```

- [ ] **Step 5: Record happening usage at most once per custom day**

In `AppModel.addHappening`, replace the unconditional `recordUse` branch with a comparison between the new entry day key and the existing happening's `lastUsedAt` converted through the same `DayBoundary.dayKey(for:dayEndHour:dayEndMinute:)`. Only call `happeningStore.recordUse` when those day keys differ.

```swift
let lastUseDayKey = happeningStore.happening(id: id)?.lastUsedAt.map {
    DayBoundary.dayKey(for: $0, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
}
if recordUse, lastUseDayKey != dayKey {
    happeningStore.recordUse(id: id, at: date)
}
```

- [ ] **Step 6: Route palette removal through the transaction**

Add a focused `removePaletteHappening(id:) -> Bool` helper in `GalleryView`. On success, assign the returned Canvas, insert the removed UUID into `pendingDeletedIds`, increment `localMutationCounter`, publish persistence, and refresh cached palette state. Before a successful re-add, remove the stable element UUID from `pendingDeletedIds` so an earlier local tombstone cannot resurrect deletion.

- [ ] **Step 7: Run tests and commit**

Run the Task 2 test command. Expected: focused tests pass.

```bash
git add StepsTrader/Views/Gallery/GalleryNotifications.swift StepsTrader/AppModel+DailyEnergy.swift StepsTrader/Views/GalleryView.swift Steps4Tests/HappeningFieldLayoutTests.swift Steps4Tests/HappeningAdditionsTests.swift
git commit -m "feat: make canvas happening removal transactional"
```

---

### Task 3: Cache exact palette assignments and preserve committed appearances

**Files:**
- Modify: `StepsTrader/Models/HappeningShapeAssignment.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Test: `Steps4Tests/HappeningFieldLayoutTests.swift`
- Test: `Steps4Tests/HappeningShapeAssignmentModelTests.swift`

**Interfaces:**
- Consumes: configured happenings, `EditorialCanvasRenderInput.sceneInput`, current Canvas elements, and colour nonce.
- Produces: `HappeningEditorialAssignmentRequest`, `HappeningEditorialAssignmentSnapshot`, and `HappeningEditorialAssignmentResolver.snapshot(request:)`.

- [ ] **Step 1: Write failing cache-key and committed-actor tests**

Cover these exact cases:

```swift
let first = HappeningEditorialAssignmentResolver.snapshot(request: request)
let second = HappeningEditorialAssignmentResolver.snapshot(request: request)
XCTAssertEqual(first, second)
XCTAssertEqual(first.request, request)
```

Create a committed `CanvasElement` with a nonzero `editorialColorVariant`, include it in the base Canvas input, and assert the assignment uses the element's actual UUID and persisted colour variant. Create an uncommitted happening and assert its preview actor's shape and `gpuAppearance` equal the actor produced after committing that stable UUID to the same base input.

- [ ] **Step 2: Run the assignment tests and verify failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeAssignmentModelTests -only-testing:Steps4Tests/HappeningFieldLayoutTests
```

Expected: compilation fails because request/snapshot types do not exist, and current resolver cannot accept committed elements.

- [ ] **Step 3: Add request and snapshot value types**

```swift
struct HappeningEditorialAssignmentRequest: Equatable {
    let happenings: [Happening]
    let baseInput: DayObjectSceneInput
    let committedElements: [CanvasElement]
    let colorNonce: UInt64
}

struct HappeningEditorialAssignmentSnapshot: Equatable {
    let request: HappeningEditorialAssignmentRequest
    let assignments: [String: HappeningEditorialAssignment]
}
```

Implement `snapshot(request:)` by reusing the existing deterministic resolver. For a committed happening, source `elementID` and `colorVariant` from the matching `CanvasElement`. For an available happening, keep the stable daily UUID and nonce-derived variant. Continue resolving each available candidate against the exact prospective final event list so preview and commit cannot diverge by slot.

- [ ] **Step 4: Store the snapshot in Gallery state rather than a computed property**

Add:

```swift
@State private var paletteAssignmentSnapshot: HappeningEditorialAssignmentSnapshot?
```

In `refreshHappeningPalette`, build the request from all configured happenings and current Canvas input. Replace the snapshot only when `snapshot?.request != request`. Make `paletteEditorialAssignments` return `paletteAssignmentSnapshot?.assignments ?? [:]`; it must no longer build ten scenes during every SwiftUI body evaluation.

- [ ] **Step 5: Run tests and commit**

Run the Task 3 command. Expected: all focused assignment tests pass.

```bash
git add StepsTrader/Models/HappeningShapeAssignment.swift StepsTrader/Views/GalleryView.swift Steps4Tests/HappeningFieldLayoutTests.swift Steps4Tests/HappeningShapeAssignmentModelTests.swift
git commit -m "perf: cache exact happening palette assignments"
```

---

### Task 4: Add palette morph, desaturation, and removal emphasis to the production actor shader

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: existing `DayObjectGPUActor` and production material fragment path.
- Produces: `paletteMorph`, `presentationSaturation`, and `removalEmphasis` actor controls while preserving exact Canvas output at their defaults.

- [ ] **Step 1: Add failing ABI and default-parity tests**

Assert the new Swift ABI and defaults:

```swift
XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.alignment, 16)
XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.stride, 80)
XCTAssertEqual(actor.paletteMorph, 1)
XCTAssertEqual(actor.presentationSaturation, 1)
XCTAssertEqual(actor.removalEmphasis, 0)
```

Extend the existing actor readback harness with three images from the same production appearance: default controls, `paletteMorph: 0`, and `presentationSaturation: 0.08`. Assert the default image remains within the existing production tolerance, the neutral image has the approved yellow edge/transparent-centre signature, and desaturation reduces RGB channel spread without changing the silhouette mask.

- [ ] **Step 2: Run the render tests and verify failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/DayObjectRenderFrameTests
```

Expected: compilation fails on the new actor controls.

- [ ] **Step 3: Extend the Swift and Metal actor records without implicit padding**

Append one 16-byte presentation block to both records:

```swift
let paletteMorph: Float
let presentationSaturation: Float
let removalEmphasis: Float
private let presentationPadding: Float
```

```metal
float paletteMorph;
float presentationSaturation;
float removalEmphasis;
float presentationPadding;
```

Set initializer defaults to `1`, `1`, and `0`, clamp each to `0...1`, update `metalStride` to `80`, update `withAppearanceIndex`, and update the Metal `static_assert` to `80`.

- [ ] **Step 4: Implement the neutral-to-production material and silhouette blend**

Pass the three controls through `DayObjectsActorVertexOut`. In the fragment:

1. calculate the current production material exactly as today;
2. calculate a sphere SDF and neutral yellow premultiplied material with centre alpha `0.10`, edge alpha `0.88`, sRGB colours `#F6B91E`, `#FFD96A`, and `#FFF0B0` converted through the existing linear-light helpers;
3. blend sphere SDF to the assigned target-shape SDF with `smoothstep(0, 1, paletteMorph)`;
4. blend neutral premultiplied material/alpha to production premultiplied material/alpha with the same progress;
5. desaturate straight RGB toward linear luminance using `presentationSaturation`, then premultiply again;
6. apply `removalEmphasis` only to a narrow inner rim using the warm linear-light equivalent of `#FF9B7A`.

At `paletteMorph == 1`, `presentationSaturation == 1`, and `removalEmphasis == 0`, return the unchanged production value so existing Canvas fixtures remain pixel-stable.

- [ ] **Step 5: Run render tests and commit**

Run the Task 4 command. Expected: the full `DayObjectRenderFrameTests` class passes, including existing perceptual fixtures.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift StepsTrader/Metal/DayObjectsActorShader.metal Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: add production palette morph controls"
```

---

### Task 5: Build ten palette actors as a pure render frame

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/HappeningPaletteRenderFrame.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: create `Steps4Tests/HappeningPaletteRenderFrameTests.swift`

**Interfaces:**
- Consumes: Task 1 slot visual states, Task 3 assignments, and `HappeningFieldLayout.Source` geometry.
- Produces: `HappeningPaletteRenderSlot`, `HappeningPaletteRenderPresentation`, `DayObjectsPresentationMode`, `HappeningPaletteTransitionTimeline`, and `HappeningPaletteRenderFrame.make(...) -> DayObjectRenderFrame`.

- [ ] **Step 1: Wire the new production and test files into the project**

Place `HappeningPaletteRenderFrame.swift` beside `DayObjectRenderFrame.swift` in the Day Objects group and add it to the Steps4 Sources phase. Place `HappeningPaletteRenderFrameTests.swift` beside `DayObjectRenderFrameTests.swift` and add it only to Steps4Tests Sources.

- [ ] **Step 2: Write failing frame-builder tests**

Construct a `390×844` viewport and ten `HappeningFieldLayout.Source` values. Assert:

```swift
XCTAssertEqual(frame.actors.count, 10)
XCTAssertEqual(available.gpuActor.paletteMorph, 0)
XCTAssertEqual(preview.gpuActor.paletteMorph, 1)
XCTAssertEqual(preview.gpuActor.shape, assignment.shape.numericValue)
XCTAssertEqual(preview.gpuAppearance, assignment.material.gpuAppearance)
XCTAssertEqual(added.gpuActor.presentationSaturation, 0.08, accuracy: 0.001)
XCTAssertEqual(removal.gpuActor.removalEmphasis, 1)
XCTAssertEqual(frame.postProcess.grainIntensity, 0.05)
XCTAssertEqual(frame.postProcess.blurRadius, 0)
```

Also assert point-to-short-side conversion: `x = (center.x - width / 2) / shortSide`, `y = (center.y - height / 2) / shortSide`, and `halfSize = radius / shortSide`.

- [ ] **Step 3: Run the new tests and verify the missing-file failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningPaletteRenderFrameTests
```

Expected: compilation fails because the render presentation types are absent.

- [ ] **Step 4: Define the render presentation types**

```swift
struct HappeningPaletteRenderSlot: Equatable {
    let happeningID: String
    let assignment: HappeningEditorialAssignment
    let visualState: HappeningPaletteSlotVisualState
    let source: HappeningFieldLayout.Source
}

struct HappeningPaletteRenderPresentation: Equatable {
    let slots: [HappeningPaletteRenderSlot]
    let viewportSize: CGSize
    let reduceMotion: Bool
    let isTransitionActive: Bool
    let backgroundRevision: UInt64
}

enum DayObjectsPresentationMode: Equatable {
    case canvas
    case happeningPalette(HappeningPaletteRenderPresentation)

    var prefersSixtyFPS: Bool {
        guard case let .happeningPalette(value) = self else { return false }
        return value.isTransitionActive
    }
}
```

- [ ] **Step 5: Implement target values and transition sampling**

Map visual states to these exact endpoints:

```swift
// morph, saturation, removal emphasis, scale, opacity, depth
case .available:        (0.00, 1.00, 0.00, 1.00, 1.00, 0.45)
case .additionPreview:  (1.00, 1.00, 0.00, 1.06, 1.00, 0.90)
case .added:            (1.00, 0.08, 0.00, 0.98, 0.82, 0.45)
case .removalPreview:   (1.00, 0.08, 1.00, 1.04, 0.88, 0.90)
```

`HappeningPaletteTransitionTimeline.update(to:elapsed:)` stores prior endpoints by happening ID and starts a `0.34` second smoothstep transition only for changed slots. `sample(at:)` interpolates controls and geometry. With Reduce Motion, it fades opacity to zero over the first `0.10` seconds, switches endpoints, and fades back over `0.10` seconds without interpolating shape geometry.

- [ ] **Step 6: Build a standard `DayObjectRenderFrame`**

Create one `DayObjectRenderActor` per slot using its exact assignment target shape/material, layout-derived position/radius, sampled controls, no trail, and no local blur. Sort by depth so armed items draw last. Use `DayObjectPostProcess(visualClarity: 1, grainSeed: scene.rootSeed, elapsed: elapsed)` for zero global blur and production grain.

- [ ] **Step 7: Run tests and commit**

Run the Task 5 command. Expected: all palette frame tests pass.

```bash
git add Steps4.xcodeproj/project.pbxproj StepsTrader/Experiments/DayObjects/HappeningPaletteRenderFrame.swift Steps4Tests/HappeningPaletteRenderFrameTests.swift
git commit -m "feat: build happening palette Metal frames"
```

---

### Task 6: Switch the existing Metal view into palette mode and eliminate redundant work

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsView.swift`
- Modify: `StepsTrader/Views/Components/DayCanvasArtworkView.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Test: `Steps4Tests/DayCanvasArtworkRoutingTests.swift`

**Interfaces:**
- Consumes: `DayObjectsPresentationMode` and `HappeningPaletteTransitionTimeline` from Task 5.
- Produces: one persistent `MTKView` whose coordinator/renderer survive Canvas↔palette mode changes, plus a testable palette background-render policy.

- [ ] **Step 1: Add failing routing and renderer-policy tests**

Assert `DayCanvasArtworkRouting` still creates exactly one Editorial branch for both `.canvas` and `.happeningPalette`. Add a pure `DayObjectsBackgroundRenderPolicy` test asserting:

```swift
XCTAssertTrue(policy.shouldRender(mode: firstPalette, targetPlan: plan))
policy.didRender(mode: firstPalette, targetPlan: plan)
XCTAssertFalse(policy.shouldRender(mode: firstPalette, targetPlan: plan))
XCTAssertTrue(policy.shouldRender(mode: changedBackgroundRevision, targetPlan: plan))
XCTAssertTrue(policy.shouldRender(mode: .canvas, targetPlan: plan))
```

Add a frame-rate test asserting 60 for an active palette transition and 30 for settled palette/Canvas.

- [ ] **Step 2: Run focused renderer tests and verify failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/DayObjectRenderFrameTests -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests
```

Expected: compilation fails on the presentation mode and policy interfaces.

- [ ] **Step 3: Thread presentation mode through the existing view chain**

Add `presentationMode: DayObjectsPresentationMode = .canvas` to `DayCanvasArtworkView`, `DayObjectsView`, and `DayObjectsMetalView`. Pass it into `DayObjectsRenderer.create` and `renderer.update`. Do not use `.id(presentationMode)` or conditionalize the `DayObjectsMetalView`; those would recreate pipelines and render targets.

- [ ] **Step 4: Select Canvas or palette frames inside `encodeFrame`**

Keep the existing insertion timeline for `.canvas`. For `.happeningPalette`, update/sample `HappeningPaletteTransitionTimeline` and call `HappeningPaletteRenderFrame.make`. Continue using the active Canvas scene for background palette and grain seed, but do not submit its Canvas actors in palette mode.

- [ ] **Step 5: Cache the palette background and reuse render targets**

Implement `DayObjectsBackgroundRenderPolicy` keyed by palette `backgroundRevision` and `DayObjectsRenderTargetPlan`. In palette mode, skip only the mesh-gradient background encoder when the key and render targets are unchanged; reuse `renderTargets.background`. In Canvas mode, preserve the current continuously animated background pass. Invalidate the policy when render targets resize or presentation returns to Canvas.

- [ ] **Step 6: Apply dynamic frame rate without a second display link**

Replace the fixed helper with:

```swift
static func configureAnimationFrameRate(_ view: MTKView, prefersSixtyFPS: Bool) {
    let preferred = prefersSixtyFPS ? 60 : 30
    if #available(iOS 15.0, *) {
        view.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(preferred),
            maximum: Float(preferred),
            preferred: Float(preferred)
        )
    } else {
        view.preferredFramesPerSecond = preferred
    }
}
```

Call it from both `makeUIView` and `updateUIView`. When the settled palette presentation is static, pause the view and request one final frame with `setNeedsDisplay`; Canvas retains its existing 30 fps behavior.

- [ ] **Step 7: Run tests and commit**

Run the Task 6 test command. Expected: focused routing and renderer tests pass with existing Canvas perceptual fixtures unchanged.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift StepsTrader/Experiments/DayObjects/DayObjectsView.swift StepsTrader/Views/Components/DayCanvasArtworkView.swift Steps4Tests/DayObjectRenderFrameTests.swift Steps4Tests/DayCanvasArtworkRoutingTests.swift
git commit -m "perf: reuse canvas renderer for happening palette"
```

---

### Task 7: Replace SwiftUI artwork with labels, badges, instructions, and toggle wiring

**Files:**
- Modify: `StepsTrader/Views/Palette/HappeningFieldLayout.swift`
- Modify: `StepsTrader/Views/Palette/HappeningFieldPresentation.swift`
- Modify: `StepsTrader/Views/Palette/HappeningShapeField.swift`
- Modify: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Modify: `StepsTrader/Localizable.xcstrings`
- Test: `Steps4Tests/HappeningFieldLayoutTests.swift`
- Test: `Steps4UITests/Steps4UITestsLaunchTests.swift`

**Interfaces:**
- Consumes: Tasks 1–6 state, assignments, transactions, presentation mode, and renderer.
- Produces: the complete touch/VoiceOver palette flow and localized contextual instruction surface.

- [ ] **Step 1: Replace disappearing-slot tests with fixed-ten toggle tests**

Update presentation tests to assert parent changes never remove a configured slot and add UI tests for this sequence:

```swift
let walk = app.buttons["happening_choice_happening_walk"]
walk.tap()
XCTAssertTrue(app.staticTexts["Tap again to add to Canvas"].waitForExistence(timeout: 1))
walk.tap()
XCTAssertEqual(walk.value as? String, "On Canvas")
XCTAssertTrue(app.otherElements["happening_status_added_happening_walk"].exists)
walk.tap()
XCTAssertTrue(app.staticTexts["Tap again to remove from Canvas"].exists)
walk.tap()
XCTAssertEqual(walk.value as? String, "Available")
XCTAssertTrue(walk.exists)
```

Also assert all ten `happening_choice_` buttons exist after add and remove, the energy bar remains, the tab bar is absent, and the list/close controls remain hittable.

- [ ] **Step 2: Run the focused model/UI tests and verify failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningFieldLayoutTests -only-testing:Steps4UITests/Steps4UITestsLaunchTests/testHappeningPaletteToggleFlow
```

Expected: assertions fail because a committed slot disappears and remove flow is absent.

- [ ] **Step 3: Make layout fixed at ten and share the exact layout with Metal**

Remove session-consumed IDs and reflow phases from `HappeningFieldPresentationState`. Its presented list is always `Array(configured.prefix(10))`. In `GalleryView`, compute one `HappeningFieldLayout.Layout` from `canvasViewportSize`, safe insets, `topCardHeight`, Dynamic Type, and the local position of `canvasAddButtonCenterY`; pass the same sources to `HappeningPaletteView` and `HappeningPaletteRenderPresentation`.

- [ ] **Step 4: Remove all SwiftUI material artwork**

Delete `HappeningEditorialCircleMaterialView`, `HappeningEditorialShapeMaterialView`, `HappeningEditorialMaterialContent`, and `HappeningEditorialShape` from `HappeningShapeField.swift`. Each slot becomes a clear `Button` with only:

- the fixed-size white two-line title;
- a small `liquidGlassControl` check badge for `.added`;
- the same badge with minus for `.removalPreview`;
- accessibility label/value/hint;
- a hit region based on the original circle source.

The button must not scale or draw a shadow around the Metal actor; selected lift is renderer-owned.

- [ ] **Step 5: Add the stable contextual instruction surface**

Create a private `HappeningPaletteInstructionView` in `HappeningPaletteView.swift`. Place it above `layout.dockAnchor` and render exactly one of:

```swift
case .add: Text("Tap again to add to Canvas")
case .added: Text("On Canvas")
case .remove: Text("Tap again to remove from Canvas")
case .error: Text("Couldn’t update Canvas. Try again.")
```

Use the selected happening title as a smaller first line. Announce every state change through `UIAccessibility.post(notification: .announcement, argument:)` with VoiceOver-specific “activate again” copy.

- [ ] **Step 6: Wire tap decisions to transactions and the renderer presentation**

Keep `HappeningPaletteInteractionState` in `GalleryView`. On `.armed`, set the 0.34-second transition-active flag and haptic. On `.perform(.add)`, call the existing exact-assignment add path with `origin: nil`. On `.perform(.remove)`, call `CanvasHappeningRemovalTransaction`. Resolve success/failure back into the state machine. Clear confirmation after `0.9` seconds without closing the palette.

Build `addedIDs` from `Set(dayCanvas.elements.map(\.optionId))`. Pass all configured happenings, never `availablePaletteHappenings()`. On close, tab departure, or day rollover, cancel interaction and transition tasks.

- [ ] **Step 7: Add localized Russian and English strings**

Add translations for the four visible lines, VoiceOver variants, added/available values, locked-slot explanation, and failure message. Preserve every unrelated `Localizable.xcstrings` edit already present in the worktree.

- [ ] **Step 8: Run tests and commit**

Run the Task 7 test command. Expected: model and UI toggle tests pass.

```bash
git add StepsTrader/Views/Palette/HappeningFieldLayout.swift StepsTrader/Views/Palette/HappeningFieldPresentation.swift StepsTrader/Views/Palette/HappeningShapeField.swift StepsTrader/Views/Palette/HappeningPaletteView.swift StepsTrader/Views/GalleryView.swift StepsTrader/Localizable.xcstrings Steps4Tests/HappeningFieldLayoutTests.swift Steps4UITests/Steps4UITestsLaunchTests.swift
git commit -m "feat: add persistent happening palette toggle UI"
```

---

### Task 8: Prevent the list editor from replacing an added happening

**Files:**
- Modify: `StepsTrader/Models/HappeningPaletteSelection.swift`
- Modify: `StepsTrader/Stores/HappeningPaletteSelectionStore.swift`
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`
- Modify: `StepsTrader/Views/Palette/HappeningChooserView.swift`
- Modify: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Test: `Steps4Tests/HappeningPaletteSelectionTests.swift`
- Test: `Steps4Tests/HappeningAdditionsTests.swift`

**Interfaces:**
- Consumes: `addedIDs` from the current `DayCanvas`.
- Produces: protected selection draft behavior and least-used replacement that excludes added IDs.

- [ ] **Step 1: Write failing protected-slot tests**

```swift
var draft = HappeningPaletteSelectionDraft(
    selected: selected,
    catalog: catalog,
    protectedIDs: [selected[0]]
)
XCTAssertEqual(draft.toggle(id: selected[0]), .protected)
XCTAssertEqual(draft.ids, selected)
```

Assert `replacementIndex(in:catalog:excluding:)` never returns a protected index, and returns `nil` when every selected ID is protected. Assert `createPaletteHappening` reports `noReplaceableSlot` rather than replacing an added happening.

- [ ] **Step 2: Run focused selection tests and verify failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningPaletteSelectionTests -only-testing:Steps4Tests/HappeningAdditionsTests
```

Expected: compilation fails because protected IDs and result cases are absent.

- [ ] **Step 3: Add protected selection semantics**

Add `.protected` to `HappeningPaletteSelectionDraftToggleResult` and `.noReplaceableSlot` to `HappeningPaletteSelectionError`. Store `protectedIDs: Set<String>` in the draft and reject removal of protected selected IDs. Change replacement selection to:

```swift
static func replacementIndex(
    in ids: [String],
    catalog: [Happening],
    excluding protectedIDs: Set<String>
) -> Int?
```

Filter indices whose IDs are protected before applying the existing use-count/date/index ordering. Thread the exclusion set through `insertReplacingLeastUsed` and `createPaletteHappening`.

- [ ] **Step 4: Explain the lock in the chooser**

Pass `protectedIDs` from `GalleryView` through `HappeningPaletteView` to `HappeningChooserView`. A protected row remains selected, shows a small lock beside its check, has accessibility value `Selected, on Canvas`, and announces `Remove this happening from Canvas before replacing it.` when activated.

- [ ] **Step 5: Run tests and commit**

Run the Task 8 command. Expected: selection and creation tests pass.

```bash
git add StepsTrader/Models/HappeningPaletteSelection.swift StepsTrader/Stores/HappeningPaletteSelectionStore.swift StepsTrader/AppModel+DailyEnergy.swift StepsTrader/Views/Palette/HappeningChooserView.swift StepsTrader/Views/Palette/HappeningPaletteView.swift StepsTrader/Views/GalleryView.swift Steps4Tests/HappeningPaletteSelectionTests.swift Steps4Tests/HappeningAdditionsTests.swift
git commit -m "feat: protect added happenings in palette editor"
```

---

### Task 9: Reconcile persisted state and verify quality on the physical device

**Files:**
- Modify: `StepsTrader/Views/GalleryView.swift`
- Modify: `StepsTrader/Views/Gallery/GalleryNotifications.swift`
- Modify: `Steps4Tests/CanvasPersistenceRegressionTests.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4UITests/Steps4UITestsLaunchTests.swift`

**Interfaces:**
- Consumes: the completed toggle flow.
- Produces: load-time reconciliation, regression coverage, physical-device performance evidence, and a Release installation for review.

- [ ] **Step 1: Add failing load-reconciliation tests**

Cover both mismatch directions:

- Canvas contains `walk`, `todayAdditions` does not: load/reconciliation creates the matching entry without incrementing use count again.
- `todayAdditions` contains `walk`, Canvas does not: load/reconciliation removes the orphan daily entry.

Assert `DayCanvas` is the visual source of truth and the result is idempotent on a second reconciliation.

- [ ] **Step 2: Implement a focused reconciliation helper**

Add the following pure types beside the spawn/removal transactions:

```swift
struct CanvasHappeningReconciliation: Equatable {
    let entriesToAdd: [OptionEntry]
    let entryIDsToRemove: [String]
}

enum CanvasHappeningReconciler {
    static func reconcile(
        canvas: DayCanvas,
        entries: [OptionEntry],
        dayKey: String,
        now: Date
    ) -> CanvasHappeningReconciliation
}
```

Match current-day Canvas elements and entries by element UUID first and `optionId` second. Treat `DayCanvas` as the visual source of truth, preserve existing matching entry IDs, and return only missing additions and orphan entry IDs. Invoke the reconciler only after the Canvas has finished loading. Apply its result through existing AppModel persistence/sync methods without recording new usage.

- [ ] **Step 3: Run the complete targeted simulator suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/HappeningPaletteInteractionTests \
  -only-testing:Steps4Tests/HappeningPaletteRenderFrameTests \
  -only-testing:Steps4Tests/HappeningFieldLayoutTests \
  -only-testing:Steps4Tests/HappeningAdditionsTests \
  -only-testing:Steps4Tests/HappeningPaletteSelectionTests \
  -only-testing:Steps4Tests/HappeningShapeAssignmentModelTests \
  -only-testing:Steps4Tests/CanvasPersistenceRegressionTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests
```

Expected: all targeted tests pass with no new warnings.

- [ ] **Step 4: Run the end-to-end UI flow**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4UITests/Steps4UITestsLaunchTests/testHappeningPaletteToggleFlow
```

Expected: the test previews, adds, arms removal, removes, and still finds all ten slots and fixed chrome.

- [ ] **Step 5: Profile the palette on iPhone Costa**

Run the existing device performance probe on device `00008130-001E3CE622C0001C` without editing or staging the concurrently-created performance scheme. Exercise palette open, neutral→preview morph, commit desaturation, removal preview, and return to neutral. Acceptance:

- no actor backlog or resource drops;
- no repeated render-target allocations during one palette session;
- one `MTKView` and one `DayObjectsRenderer` coordinator;
- 60 fps target during the three 0.34-second transitions;
- settled palette returns to 30 fps or paused static rendering;
- renderer target memory stays within the existing 80 MiB device budget.

- [ ] **Step 6: Perform the bounded visual review**

Capture one initial, one addition-preview, one added, and one removal-preview screenshot on the shipped iPhone class. Verify: production grain is visible, neutral circles are materially equal, preview equals the final Canvas actor, labels remain readable, no badge escapes its slot, no object clips against screen edges, and the instruction surface does not collide with bottom controls. Fix all observed defects in one batch and confirm with one final screenshot pass.

- [ ] **Step 7: Build and install a Release review build**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'id=00008130-001E3CE622C0001C' build
```

Install the resulting `Nowhere.app` through `xcrun devicectl device install app --device 43B6B950-DBCA-50C3-AE14-FBD518808E3B <absolute-built-app-path>`. Launch when the device is unlocked and compare interaction feel against Debug.

- [ ] **Step 8: Commit reconciliation and verification fixtures**

```bash
git add StepsTrader/Views/GalleryView.swift StepsTrader/Views/Gallery/GalleryNotifications.swift Steps4Tests/CanvasPersistenceRegressionTests.swift Steps4Tests/DayObjectRenderFrameTests.swift Steps4UITests/Steps4UITestsLaunchTests.swift
git commit -m "test: verify persistent happening palette toggles"
```

- [ ] **Step 9: Review the branch delta before updating the PR**

```bash
git status --short
git log --oneline --decorate -12
git diff --check HEAD~9..HEAD
git diff --stat 055208d..HEAD
```

Expected: each task has its own commit, no unrelated dirty file is staged, whitespace checks pass, and the PR delta contains the approved palette architecture plus pre-existing Current Integrations work only.

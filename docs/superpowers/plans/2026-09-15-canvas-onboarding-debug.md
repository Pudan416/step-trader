# Canvas onboarding DEBUG Implementation Plan

**Goal:** Implement the supplied 15 September Canvas onboarding specification on the real application, based on integration 16a17ddc.
**Architecture:** A DEBUG-only observable coordinator owns persisted tour progress and guarded result events. Product controls keep their handlers and expose semantic anchors/quiet modifiers. Root and sheet hosts stay in their own coordinate spaces. No production analytics, fixture writes, economic changes, or first-run replacement.
**Tech Stack:** SwiftUI, Foundation reducer tests, existing Health/FamilyControls/auth/export services.
**Spec:** User-provided “Nowhere — Canvas onboarding” specification, sections 1–18 in this task.

## Global Constraints
- Live mutations use existing product services. No automatic grants or destructive resets.
- Start begins at Welcome; Resume is explicit. Stop/Restart invalidate pending operations.
- Only confirmed expected results advance. Picker commit and dismiss are separate events.
- Feeds/Me navigation requires the user's tab action.
- Release and existing first-run remain unchanged. No device installation requested.
- Health query completion is not proof of read authorization.

## Shared interfaces
`DebugCanvasTour.shared` (@Observable, @MainActor, DEBUG only).
`step: CanvasTourStep`, `isActive: Bool`, `selectedGroupID: String?`.
`send(_ event: CanvasTourEvent, token: CanvasTourOperation? = nil)`.
`beginOperation(_ name: String, returnContext: String = "flow") -> CanvasTourOperation?` captures session and operation ID; nil outside tour.
`sheetPresented(_ name: String, returnContext: String = "flow")`, `sheetDismissed(_ name: String)`.
`report(_ message: String)` records non-sensitive diagnostics; `recover(_ message: String)` records retryable error.
`View.canvasTourControl(_ id: String)` registers target + per-control policy; release identity.
`View.canvasTourAnchor(_ id: String)` registers information-only target; release identity.
`View.canvasTourHost(model: AppModel, context: String = "root")` only where explicitly required.

Steps: welcome, add, happening, balance, healthValue, healthResult, feedsTab, addApps, selectionResult, selectFeed, chooseDuration, meTab, saveDays, setup, poster, finish.
Events: begin, palettePresented, happeningAdded(String), paletteDismissed, dataPanelExpanded, healthUpdated, healthDeferred, continueHealth, tabSelected(Int), appSelectionCommitted(String), selectionAcknowledged, groupOpened(String), unlockSucceeded(String), posterReady(String), showSetup, setupCompleted, shareDismissed(Bool), exportSkipped, finish, skipRequested.

## Tasks
- [x] 1. Coordinator/guards/persistence/diagnostics/root host/Developer entry and invariant tests. Parent owns MainTabView, new CanvasTour core/UI files, project registration.
- [x] 2. Canvas live palette commit/dismiss and drawer state hooks; quiet modifiers on actual Canvas controls; prevent competing hints. Delegate owns GalleryView and Gallery/Palette controls only.
- [x] 3. Feeds authorization/picker result/dismiss/selected group/duration/unlock hooks with semantic controls. Delegate owns AppsPageSimplified, Feeds and picker components only.
- [x] 4. Me readiness/share results and optional setup checklist using existing services/views. Delegate owns MeView/MeViewSupport and new DebugCanvasTourSetup.swift only.
- [x] 5. Build DEBUG and Release, run reducer/integration tests, simulator UI verification, cross-file review and fixes; document unverified physical-device branches and Live data effects.

## Verification cases
Reject unexpected/duplicate events and stale operation/session callbacks; stop/reset preserves model; mutation waits for palette/picker dismissal; cancelled picker retries; missing group recovers; optional setup/export advances without false success; anchors missing do not auto-complete. Run dedicated Steps4 scheme builds in isolated DerivedData and target tests. Existing tests for palette interaction, transactions, permissions, main tabs and inline purchases supply product contracts.

## Result
Implementation and automated checks completed. See [verification report](../../reports/2026-09-15-canvas-onboarding-debug.md) for the passing suites, simulator evidence, Live test-data effects and outstanding physical-device acceptance matrix. No physical-device installation or remote publication performed.

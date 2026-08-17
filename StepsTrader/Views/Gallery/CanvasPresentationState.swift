import Foundation

/// The Canvas screen's four mutually exclusive presentation states.
///
/// This replaces the old `isWideCanvas` + `editState.isEditMode` pair, whose
/// product allowed states the design forbids: a data sheet over a full-screen
/// canvas, edit mode without full screen, chrome floating over an expanded
/// canvas. Here those are simply not spellable.
enum CanvasPresentationState: String, CaseIterable, Equatable {
    /// Canvas with the status pill and the three-control bottom row.
    case canvas
    /// Canvas with the data bottom sheet over it. Pill and row stay put.
    case data
    /// Chrome-free canvas with a viewing dock. Never an editing state.
    case fullScreen
    /// Chrome-free canvas with Done + Remix and draggable elements.
    case editing
}

/// Everything that can move the Canvas screen between states.
enum CanvasPresentationEvent: Equatable {
    case showData
    case hideData
    case enterFullScreen
    case exitFullScreen
    case beginEditing
    case endEditing
    /// The happening palette is opening; the canvas must be visible behind it.
    case openHappeningPalette
    /// The user switched to Feeds or Me.
    case leftCanvasTab
    /// The custom day rolled over while a state was open.
    case dayBoundary
}

extension CanvasPresentationState {

    // MARK: - Derived chrome

    /// Matches the legacy `isWideCanvas` binding `MainTabView` reads to hide
    /// the tab bar and the top pill.
    var isWideCanvas: Bool { self == .fullScreen || self == .editing }

    var isEditing: Bool { self == .editing }

    var showsStatusPill: Bool { self == .canvas || self == .data }

    var showsBottomActionRow: Bool { self == .canvas || self == .data }

    var showsDataPanel: Bool { self == .data }

    var showsFullScreenDock: Bool { self == .fullScreen }

    var showsEditingChrome: Bool { self == .editing }

    // MARK: - Transitions

    /// The full transition table. Anything not listed leaves the state alone:
    /// a stray event should be inert, never a surprise navigation.
    func applying(_ event: CanvasPresentationEvent) -> CanvasPresentationState {
        switch event {
        case .leftCanvasTab, .dayBoundary:
            // Both collapse everything: the tab bar is hidden while wide, and a
            // new day must not inherit the previous day's presentation.
            return .canvas

        case .showData:
            return self == .canvas ? .data : self

        case .hideData:
            return self == .data ? .canvas : self

        case .enterFullScreen:
            // Any non-full-screen state (including a stray application while
            // already `.editing`) resolves to the plain viewing full screen —
            // this event alone must never leave an edit in progress.
            return self == .fullScreen ? self : .fullScreen

        case .exitFullScreen:
            return isWideCanvas ? .canvas : self

        case .beginEditing:
            return self == .fullScreen ? .editing : self

        case .endEditing:
            return self == .editing ? .fullScreen : self

        case .openHappeningPalette:
            // The palette never presents over a wide canvas, so it cannot
            // collapse one either.
            return isWideCanvas ? self : .canvas
        }
    }

    // MARK: - Analytics

    /// Event name for a completed transition, or `nil` when nothing moved.
    /// Names only — never energy values, HealthKit values, happening labels or
    /// element IDs.
    static func analyticsEventName(
        from old: CanvasPresentationState,
        to new: CanvasPresentationState
    ) -> String? {
        guard old != new else { return nil }
        switch (old, new) {
        case (.canvas, .data):           return "canvas_data_opened"
        case (.data, .canvas):           return "canvas_data_closed"
        case (_, .fullScreen) where !old.isWideCanvas: return "canvas_fullscreen_entered"
        case (.fullScreen, .editing):    return "canvas_edit_entered"
        case (.editing, .fullScreen):    return "canvas_edit_exited"
        case (_, _) where old.isWideCanvas && !new.isWideCanvas:
            return "canvas_fullscreen_exited"
        default:                         return nil
        }
    }
}

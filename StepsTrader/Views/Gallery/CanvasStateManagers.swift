import SwiftUI

// MARK: - Canvas Edit State

/// Edit-mode state hoisted out of GalleryView. Owns transient UI state for
/// drag/dice/tap interactions on the wide canvas. Resetting back to a
/// neutral state happens via `reset()`.
@Observable
final class CanvasEditState {
    var isEditMode: Bool = false
    var editFreezeTime: Date? = nil
    var isDraggingElement: Bool = false
    var dragStartBasePosition: CGPoint? = nil
    var activeElementId: UUID? = nil

    func reset() {
        isEditMode = false
        editFreezeTime = nil
        isDraggingElement = false
        dragStartBasePosition = nil
        activeElementId = nil
    }

    func cancelDrag() {
        isDraggingElement = false
        dragStartBasePosition = nil
    }
}

// MARK: - Canvas Toolbar State

/// Toolbar / sheet state hoisted out of GalleryView. Drives the category
/// picker, share sheet, save-routine alert, and export progress indicator.
@Observable
final class CanvasToolbarState {
    var pickerCategory: EnergyCategory? = nil
    var showShareSheet: Bool = false
    var shareImage: UIImage? = nil
    var isExporting: Bool = false
    var showSaveRoutine: Bool = false
    var routineName: String = ""

    func clearShareSheet() {
        showShareSheet = false
        shareImage = nil
    }
}

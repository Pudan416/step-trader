import Foundation

enum HappeningPaletteMutation: Equatable {
    case add(String)
    case remove(String)

    var id: String {
        switch self {
        case let .add(id), let .remove(id):
            id
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

    var awaitsConfirmation: Bool {
        self == .additionPreview || self == .removalPreview
    }
}

enum HappeningPaletteConfirmation: Equatable {
    case added(String)
    case removed(String)
}

enum HappeningPaletteSuccessHaptic: Equatable {
    case addition
    case removal

    static func forMutation(_ mutation: HappeningPaletteMutation) -> Self {
        switch mutation {
        case .add: .addition
        case .remove: .removal
        }
    }
}

enum HappeningPaletteAccessibility {
    static func value(for state: HappeningPaletteSlotVisualState) -> String {
        switch state {
        case .available: String(localized: "Available")
        case .additionPreview: String(localized: "Previewing addition to Canvas")
        case .added: String(localized: "On Canvas")
        case .removalPreview: String(localized: "Previewing removal from Canvas")
        }
    }
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
        guard succeeded else {
            if case .remove = mutation {
                armedMutation = nil
            }
            return
        }

        armedMutation = nil
        confirmation = switch mutation {
        case let .add(id):
            .added(id)
        case let .remove(id):
            .removed(id)
        }
    }

    mutating func clearConfirmation() {
        confirmation = nil
    }

    mutating func cancel() {
        armedMutation = nil
        pendingMutation = nil
        confirmation = nil
    }

    func visualState(for id: String, addedIDs: Set<String>) -> HappeningPaletteSlotVisualState {
        if armedMutation == .add(id) {
            return .additionPreview
        }

        if armedMutation == .remove(id) {
            return .removalPreview
        }

        return addedIDs.contains(id) ? .added : .available
    }
}

#if os(macOS)
import Foundation
import SwiftUI

@MainActor
final class MacHabitCommandModel: ObservableObject {
    @Published var selectedMode: MainListMode = .habits

    var onAdd: () -> Void = {}
    var onSelectHabits: () -> Void = {}
    var onSelectThings: () -> Void = {}
    var onShowSettings: () -> Void = {}

    var addTitle: String {
        selectedMode == .habits ? "New Habit" : "New Thing"
    }

    func add() {
        onAdd()
    }

    func selectHabits() {
        onSelectHabits()
    }

    func selectThings() {
        onSelectThings()
    }

    func showSettings() {
        onShowSettings()
    }
}

private struct MacHabitCommandFocusedValueKey: FocusedValueKey {
    typealias Value = MacHabitCommandModel
}

extension FocusedValues {
    var macHabitCommands: MacHabitCommandModel? {
        get { self[MacHabitCommandFocusedValueKey.self] }
        set { self[MacHabitCommandFocusedValueKey.self] = newValue }
    }
}
#endif

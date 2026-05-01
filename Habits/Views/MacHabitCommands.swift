#if os(macOS)
import SwiftUI

struct MacHabitCommands: Commands {
    @FocusedValue(\.macHabitCommands) private var commandModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(commandModel?.addTitle ?? "New Habit") {
                commandModel?.add()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings") {
                commandModel?.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("View") {
            Button("Habits") {
                commandModel?.selectHabits()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Things") {
                commandModel?.selectThings()
            }
            .keyboardShortcut("2", modifiers: .command)
        }
    }
}
#endif

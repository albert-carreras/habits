import Foundation
import SwiftData

@Model
final class HabitCompletion {
    var id: UUID
    var date: Date
    var count: Int
    var habit: Habit?

    init(date: Date = .now, count: Int = 1, habit: Habit? = nil) {
        self.id = UUID()
        self.date = date
        self.count = count
        self.habit = habit
    }
}

import Foundation
import SwiftData

enum HabitFrequency: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    case custom = "Custom"

    var id: String { rawValue }
}

enum CustomIntervalUnit: String, Codable, CaseIterable, Identifiable {
    case days = "Days"
    case weeks = "Weeks"
    case months = "Months"

    var id: String { rawValue }
}

@Model
final class Habit {
    var id: UUID
    var name: String
    var frequency: HabitFrequency
    var customIntervalValue: Int?
    var customIntervalUnit: CustomIntervalUnit?
    var timesToComplete: Int
    var startDate: Date
    var notificationsEnabled: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    var completions: [HabitCompletion] = []

    init(
        name: String,
        frequency: HabitFrequency = .daily,
        customIntervalValue: Int? = nil,
        customIntervalUnit: CustomIntervalUnit? = nil,
        timesToComplete: Int = 1,
        startDate: Date = .now,
        notificationsEnabled: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.frequency = frequency
        self.customIntervalValue = customIntervalValue
        self.customIntervalUnit = customIntervalUnit
        self.timesToComplete = timesToComplete
        self.startDate = startDate
        self.notificationsEnabled = notificationsEnabled
        self.createdAt = .now
    }
}

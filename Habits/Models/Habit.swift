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
    static let maxNameLength = 100
    static let maxTimesToComplete = 9999
    static let maxCustomIntervalValue = 365
    static let defaultNotificationHour = 9
    static let defaultNotificationMinute = 0

    var id: UUID
    var name: String
    var frequency: HabitFrequency
    var customIntervalValue: Int?
    var customIntervalUnit: CustomIntervalUnit?
    var timesToComplete: Int
    var startDate: Date
    var notificationsEnabled: Bool
    var notificationHour: Int?
    var notificationMinute: Int?
    var createdAt: Date
    var syncUpdatedAt: Date?
    var syncDeletedAt: Date?
    var syncRemoteUpdatedAt: Date?
    var syncNeedsPush: Bool?

    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    var completions: [HabitCompletion] = []

    init(
        id: UUID = UUID(),
        name: String,
        frequency: HabitFrequency = .daily,
        customIntervalValue: Int? = nil,
        customIntervalUnit: CustomIntervalUnit? = nil,
        timesToComplete: Int = 1,
        startDate: Date = .now,
        notificationsEnabled: Bool = false,
        notificationHour: Int? = nil,
        notificationMinute: Int? = nil,
        createdAt: Date = .now,
        syncUpdatedAt: Date? = .now,
        syncDeletedAt: Date? = nil,
        syncRemoteUpdatedAt: Date? = nil,
        syncNeedsPush: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.customIntervalValue = customIntervalValue
        self.customIntervalUnit = customIntervalUnit
        self.timesToComplete = timesToComplete
        self.startDate = startDate
        self.notificationsEnabled = notificationsEnabled
        self.notificationHour = notificationHour
        self.notificationMinute = notificationMinute
        self.createdAt = createdAt
        self.syncUpdatedAt = syncUpdatedAt
        self.syncDeletedAt = syncDeletedAt
        self.syncRemoteUpdatedAt = syncRemoteUpdatedAt
        self.syncNeedsPush = syncNeedsPush
    }

    var resolvedNotificationHour: Int {
        guard let notificationHour, (0...23).contains(notificationHour) else {
            return Self.defaultNotificationHour
        }

        return notificationHour
    }

    var resolvedNotificationMinute: Int {
        guard let notificationMinute, (0...59).contains(notificationMinute) else {
            return Self.defaultNotificationMinute
        }

        return notificationMinute
    }
}

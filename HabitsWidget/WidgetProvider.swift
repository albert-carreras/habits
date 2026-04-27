import WidgetKit
import SwiftUI
import AppIntents

struct HabitWidgetEntry: TimelineEntry {
    let date: Date
    let habitID: UUID?
    let habitName: String
    let isCompleted: Bool
    let completionCount: Int
    let timesToComplete: Int
    let streakDays: Int
    let isDueToday: Bool
}

struct HabitWidgetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
    static let defaultQuery = HabitWidgetEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitWidgetEntityQuery: EntityQuery {
    func entities(for identifiers: [HabitWidgetEntity.ID]) async throws -> [HabitWidgetEntity] {
        HabitWidgetDataStore.loadSnapshot().habits
            .filter { identifiers.contains($0.id) }
            .map { HabitWidgetEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [HabitWidgetEntity] {
        HabitWidgetDataStore.loadSnapshot().habits
            .map { HabitWidgetEntity(id: $0.id, name: $0.name) }
    }
}

struct HabitSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Habit"
    static let description: IntentDescription = IntentDescription("Choose which habit to display")

    @Parameter(title: "Habit")
    var habit: HabitWidgetEntity?

    init() {}

    init(habit: HabitWidgetEntity?) {
        self.habit = habit
    }
}

struct HabitWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = HabitWidgetEntry
    typealias Intent = HabitSelectionIntent

    func placeholder(in context: Context) -> HabitWidgetEntry {
        HabitWidgetEntry(
            date: .now,
            habitID: nil,
            habitName: "Exercise",
            isCompleted: false,
            completionCount: 0,
            timesToComplete: 1,
            streakDays: 5,
            isDueToday: true
        )
    }

    func snapshot(for configuration: HabitSelectionIntent, in context: Context) async -> HabitWidgetEntry {
        fetchEntry(habitID: configuration.habit?.id, date: .now)
    }

    func timeline(for configuration: HabitSelectionIntent, in context: Context) async -> Timeline<HabitWidgetEntry> {
        let now = Date.now
        let entry = fetchEntry(habitID: configuration.habit?.id, date: now)
        let nextUpdate = nextRefreshDate(after: now)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func fetchEntry(habitID: UUID?, date: Date = .now) -> HabitWidgetEntry {
        let snapshot = HabitWidgetDataStore.loadSnapshot()
        let selectedHabit = habitID.flatMap { selectedID in
            snapshot.habits.first { $0.id == selectedID }
        } ?? snapshot.habits.first

        guard let selectedHabit else {
            return HabitWidgetEntry(
                date: .now,
                habitID: nil,
                habitName: "No habits yet",
                isCompleted: false,
                completionCount: 0,
                timesToComplete: 1,
                streakDays: 0,
                isDueToday: true
            )
        }

        let isDueToday = selectedHabit.isScheduled(on: date)
        return HabitWidgetEntry(
            date: date,
            habitID: selectedHabit.id,
            habitName: selectedHabit.name,
            isCompleted: isDueToday && selectedHabit.isCompleted(on: date),
            completionCount: isDueToday ? selectedHabit.completionCount(on: date) : 0,
            timesToComplete: selectedHabit.timesToComplete,
            streakDays: selectedHabit.streakDays(endingAt: date),
            isDueToday: isDueToday
        )
    }

    private func nextRefreshDate(after date: Date) -> Date {
        let calendar = Calendar.current
        let thirtyMinutes = calendar.date(byAdding: .minute, value: 30, to: date) ?? date
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? thirtyMinutes
        return min(thirtyMinutes, nextMidnight)
    }
}

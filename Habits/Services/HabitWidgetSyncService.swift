import Foundation
import SwiftData
import WidgetKit

enum HabitWidgetSyncService {
    @discardableResult
    static func sync(context: ModelContext, date: Date = .now) -> Bool {
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.name)])
        guard let habits = try? context.fetch(descriptor) else { return false }

        return sync(habits: habits, date: date)
    }

    @discardableResult
    static func sync(habits: [Habit], date: Date = .now) -> Bool {
        guard !AppEnvironment.disablesWidgetSync else { return true }

        let snapshot = makeSnapshot(habits: habits, date: date)
        do {
            try HabitWidgetDataStore.saveSnapshot(snapshot)
        } catch {
            #if DEBUG
            print("HabitWidgetSyncService failed to save snapshot: \(error)")
            #endif
            return false
        }
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    static func makeSnapshot(habits: [Habit], date: Date = .now) -> HabitWidgetSnapshot {
        HabitWidgetSnapshot(
            generatedAt: date,
            habits: habits.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { widgetItem(for: $0, date: date) }
        )
    }

    static func widgetItem(for habit: Habit, date: Date = .now) -> HabitWidgetItem {
        HabitWidgetItem(
            id: habit.id,
            name: habit.name,
            completionCount: completionCount(for: habit, on: date),
            timesToComplete: habit.timesToComplete,
            streakDays: streakDays(for: habit, endingAt: date),
            frequencyRawValue: habit.frequency.rawValue,
            customIntervalValue: habit.customIntervalValue,
            customIntervalUnitRawValue: habit.customIntervalUnit?.rawValue,
            startDate: habit.startDate,
            completions: habit.completions.map {
                HabitWidgetCompletion(date: $0.date, count: $0.count)
            }
        )
    }

    private static func completionCount(for habit: Habit, on date: Date) -> Int {
        let periodStart = DateHelpers.periodStart(
            for: date,
            frequency: habit.frequency,
            customValue: habit.customIntervalValue,
            customUnit: habit.customIntervalUnit,
            habitStart: habit.startDate
        )
        let periodEnd = DateHelpers.periodEnd(
            for: periodStart,
            frequency: habit.frequency,
            customValue: habit.customIntervalValue,
            customUnit: habit.customIntervalUnit
        )

        return habit.completions
            .filter { $0.date >= periodStart && $0.date < periodEnd }
            .reduce(0) { $0 + $1.count }
    }

    private static func streakDays(for habit: Habit, endingAt date: Date) -> Int {
        let calendar = Calendar.current
        let habitStart = calendar.startOfDay(for: habit.startDate)
        var streak = 0
        var cursor = date

        while cursor >= habitStart && streak < 366 {
            if DateHelpers.isScheduled(
                on: cursor,
                frequency: habit.frequency,
                customValue: habit.customIntervalValue,
                customUnit: habit.customIntervalUnit,
                habitStart: habit.startDate
            ) {
                guard completionCount(for: habit, on: cursor) >= habit.timesToComplete else { break }
                streak += 1
            }
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }
}

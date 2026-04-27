import SwiftUI
import SwiftData

@Observable
final class HabitListViewModel {
    var showingAddSheet = false
    var habitToEdit: Habit?
    var habitToDelete: Habit?
    var showingDeleteConfirmation = false

    func completionCount(for habit: Habit, on date: Date = .now) -> Int {
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

    func isCompleted(habit: Habit, on date: Date = .now) -> Bool {
        completionCount(for: habit, on: date) >= habit.timesToComplete
    }

    func isDueToday(_ habit: Habit, on date: Date = .now) -> Bool {
        DateHelpers.isScheduled(
            on: date,
            frequency: habit.frequency,
            customValue: habit.customIntervalValue,
            customUnit: habit.customIntervalUnit,
            habitStart: habit.startDate
        )
    }

    func nextDueDate(for habit: Habit, on date: Date = .now) -> Date {
        DateHelpers.nextScheduledDate(
            onOrAfter: date,
            frequency: habit.frequency,
            customValue: habit.customIntervalValue,
            customUnit: habit.customIntervalUnit,
            habitStart: habit.startDate
        )
    }

    func toggleCompletion(for habit: Habit, context: ModelContext) {
        let now = Date.now
        let periodStart = DateHelpers.periodStart(
            for: now,
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

        if let existing = habit.completions.first(where: { $0.date >= periodStart && $0.date < periodEnd }) {
            context.delete(existing)
        } else {
            let completion = HabitCompletion(date: now, count: 1, habit: habit)
            context.insert(completion)
        }

        saveAndSync(context: context)
    }

    func logHabitTap(for habit: Habit, context: ModelContext) {
        if habit.timesToComplete > 1 {
            incrementCompletion(for: habit, context: context)
        } else {
            toggleCompletion(for: habit, context: context)
        }
    }

    func incrementCompletion(for habit: Habit, context: ModelContext) {
        guard !isCompleted(habit: habit) else { return }

        let now = Date.now
        let periodStart = DateHelpers.periodStart(
            for: now,
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

        if let existing = habit.completions.first(where: { $0.date >= periodStart && $0.date < periodEnd }) {
            existing.count += 1
        } else {
            let completion = HabitCompletion(date: now, count: 1, habit: habit)
            context.insert(completion)
        }

        saveAndSync(context: context)
    }

    func clearCompletion(for habit: Habit, context: ModelContext) {
        let now = Date.now
        let periodStart = DateHelpers.periodStart(
            for: now,
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

        let toRemove = habit.completions.filter { $0.date >= periodStart && $0.date < periodEnd }
        for completion in toRemove {
            context.delete(completion)
        }

        saveAndSync(context: context)
    }

    func addCompletion(for habit: Habit, amount: Int, context: ModelContext) {
        let now = Date.now
        let periodStart = DateHelpers.periodStart(
            for: now,
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

        let currentCount = completionCount(for: habit)
        let remaining = max(0, habit.timesToComplete - currentCount)
        let toAdd = min(amount, remaining)
        guard toAdd > 0 else { return }

        if let existing = habit.completions.first(where: { $0.date >= periodStart && $0.date < periodEnd }) {
            existing.count += toAdd
        } else {
            let completion = HabitCompletion(date: now, count: toAdd, habit: habit)
            context.insert(completion)
        }

        saveAndSync(context: context)
    }

    func deleteHabit(_ habit: Habit, context: ModelContext) {
        NotificationService.removeNotification(for: habit)
        context.delete(habit)
        saveAndSync(context: context)
    }

    func frequencyLabel(for habit: Habit) -> String {
        switch habit.frequency {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom:
            let value = habit.customIntervalValue ?? 1
            let unit = habit.customIntervalUnit ?? .days
            let unitName = value == 1 ? String(unit.rawValue.dropLast()).lowercased() : unit.rawValue.lowercased()
            return "Every \(value) \(unitName)"
        }
    }

    func scheduleLabel(for habit: Habit, on date: Date = .now) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let nextDueDate = nextDueDate(for: habit, on: today)

        if calendar.isDate(nextDueDate, inSameDayAs: today) {
            return "Today"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(nextDueDate, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }

        if let weekFromToday = calendar.date(byAdding: .day, value: 7, to: today),
           nextDueDate < weekFromToday {
            return nextDueDate.formatted(.dateTime.weekday(.abbreviated))
        }

        return nextDueDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func saveAndSync(context: ModelContext) {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("HabitListViewModel failed to save context: \(error)")
            #endif
        }

        HabitWidgetSyncService.sync(context: context)
    }
}

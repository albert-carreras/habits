import SwiftUI
import SwiftData

@MainActor
@Observable
final class HabitListViewModel {
    var activeSheet: HabitListSheet?
    var deleteTarget: HabitListDeleteTarget?
    var showingDeleteConfirmation = false

    var showingAddSheet: Bool {
        get {
            if case .add = activeSheet { return true }
            return false
        }
        set {
            if newValue {
                presentAddSheet()
            } else if showingAddSheet {
                activeSheet = nil
            }
        }
    }

    var habitToEdit: Habit? {
        get {
            if case .edit(let habit) = activeSheet { return habit }
            return nil
        }
        set {
            if let newValue {
                presentEditSheet(for: newValue)
            } else if habitToEdit != nil {
                activeSheet = nil
            }
        }
    }

    func presentAddSheet() {
        activeSheet = .add
    }

    func presentAddSheet(for mode: MainListMode) {
        switch mode {
        case .habits:
            activeSheet = .add
        case .things:
            activeSheet = .addThing
        }
    }

    func presentEditSheet(for habit: Habit) {
        activeSheet = .edit(habit)
    }

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
            .filter { $0.syncDeletedAt == nil && $0.date >= periodStart && $0.date < periodEnd }
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

        if let existing = completion(for: habit, periodStart: periodStart, periodEnd: periodEnd) {
            if existing.syncDeletedAt == nil {
                markCompletionDeleted(existing)
            } else {
                existing.syncDeletedAt = nil
                existing.count = 1
                existing.date = now
                existing.periodStart = periodStart
                markDirty(existing)
            }
        } else {
            let completion = HabitCompletion(date: now, periodStart: periodStart, count: 1, habit: habit)
            markDirty(completion)
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
        rescheduleNotificationIfNeeded(for: habit)
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

        if let existing = completion(for: habit, periodStart: periodStart, periodEnd: periodEnd) {
            existing.syncDeletedAt = nil
            existing.count += 1
            existing.date = now
            existing.periodStart = periodStart
            markDirty(existing)
        } else {
            let completion = HabitCompletion(date: now, periodStart: periodStart, count: 1, habit: habit)
            markDirty(completion)
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

        let toRemove = habit.completions.filter { $0.syncDeletedAt == nil && $0.date >= periodStart && $0.date < periodEnd }
        for completion in toRemove {
            markCompletionDeleted(completion)
        }

        rescheduleNotificationIfNeeded(for: habit)
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

        if let existing = completion(for: habit, periodStart: periodStart, periodEnd: periodEnd) {
            existing.syncDeletedAt = nil
            existing.count += toAdd
            existing.date = now
            existing.periodStart = periodStart
            markDirty(existing)
        } else {
            let completion = HabitCompletion(date: now, periodStart: periodStart, count: toAdd, habit: habit)
            markDirty(completion)
            context.insert(completion)
        }

        rescheduleNotificationIfNeeded(for: habit)
        saveAndSync(context: context)
    }

    func deleteHabit(_ habit: Habit, context: ModelContext) {
        NotificationService.removeNotification(for: habit)
        markDirty(habit, deletedAt: .now)
        for completion in habit.completions where completion.syncDeletedAt == nil {
            markCompletionDeleted(completion)
        }
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
            return
        }

        SyncService.schedulePush(context: context)
        HabitWidgetSyncService.sync(context: context)
    }

    private func completion(for habit: Habit, periodStart: Date, periodEnd: Date) -> HabitCompletion? {
        habit.completions.first {
            $0.periodStart == periodStart || ($0.date >= periodStart && $0.date < periodEnd)
        }
    }

    private func rescheduleNotificationIfNeeded(for habit: Habit) {
        guard habit.notificationsEnabled else { return }
        Task {
            await NotificationService.scheduleNotification(for: habit)
        }
    }

    private func markCompletionDeleted(_ completion: HabitCompletion) {
        completion.count = 0
        markDirty(completion, deletedAt: .now)
    }

    private func markDirty(_ habit: Habit, deletedAt: Date? = nil) {
        habit.syncUpdatedAt = .now
        habit.syncDeletedAt = deletedAt
        habit.syncNeedsPush = true
    }

    private func markDirty(_ completion: HabitCompletion, deletedAt: Date? = nil) {
        completion.syncUpdatedAt = .now
        completion.syncDeletedAt = deletedAt
        completion.syncNeedsPush = true
    }
}

enum HabitListSheet: Identifiable {
    case add
    case edit(Habit)
    case addThing
    case editThing(Thing)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let habit):
            return "edit-\(habit.id.uuidString)"
        case .addThing:
            return "add-thing"
        case .editThing(let thing):
            return "edit-thing-\(thing.id.uuidString)"
        }
    }
}

enum HabitListDeleteTarget {
    case habit(Habit)
    case thing(Thing)

    var title: String {
        switch self {
        case .habit:
            return "Delete Habit"
        case .thing:
            return "Delete Thing"
        }
    }

    var message: String {
        switch self {
        case .habit(let habit):
            return "Are you sure you want to delete \"\(habit.name)\"? This cannot be undone."
        case .thing(let thing):
            return "Are you sure you want to delete \"\(thing.title)\"? This cannot be undone."
        }
    }
}

enum MainListMode: String, CaseIterable, Identifiable {
    case habits
    case things

    var id: String { rawValue }

    var title: String {
        switch self {
        case .habits: return "Habits"
        case .things: return "Things"
        }
    }

}

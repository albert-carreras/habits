import Testing
import Foundation
import SwiftData
@testable import Habits

@Suite("ViewModel + SwiftData Integration")
@MainActor
struct ViewModelIntegrationTests {
    let viewModel = HabitListViewModel()

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Habit.self, HabitCompletion.self, configurations: config)
        return ModelContext(container)
    }

    @Test("Increment creates a completion record")
    @MainActor
    func incrementCreatesCompletion() throws {
        let context = try makeContext()
        let habit = Habit(name: "Test", timesToComplete: 5)
        context.insert(habit)
        try context.save()

        viewModel.incrementCompletion(for: habit, context: context)
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 1)
    }

    @Test("Increment reuses existing completion in same period")
    @MainActor
    func incrementReusesCompletion() throws {
        let context = try makeContext()
        let habit = Habit(name: "Test", timesToComplete: 10)
        context.insert(habit)
        try context.save()

        viewModel.incrementCompletion(for: habit, context: context)
        viewModel.incrementCompletion(for: habit, context: context)
        viewModel.incrementCompletion(for: habit, context: context)
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 3)
        #expect(habit.completions.count == 1)
    }

    @Test("Increment stops at timesToComplete")
    @MainActor
    func incrementStopsAtTarget() throws {
        let context = try makeContext()
        let habit = Habit(name: "Test", timesToComplete: 2)
        context.insert(habit)
        try context.save()

        viewModel.incrementCompletion(for: habit, context: context)
        viewModel.incrementCompletion(for: habit, context: context)
        viewModel.incrementCompletion(for: habit, context: context) // should not increment
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 2)
        #expect(viewModel.isCompleted(habit: habit))
    }

    @Test("addCompletion with specific amount")
    @MainActor
    func addCompletionAmount() throws {
        let context = try makeContext()
        let habit = Habit(name: "Pushups", timesToComplete: 50)
        context.insert(habit)
        try context.save()

        viewModel.addCompletion(for: habit, amount: 25, context: context)
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 25)
    }

    @Test("addCompletion caps at remaining")
    @MainActor
    func addCompletionCapsAtRemaining() throws {
        let context = try makeContext()
        let habit = Habit(name: "Pushups", timesToComplete: 50)
        context.insert(habit)
        try context.save()

        viewModel.addCompletion(for: habit, amount: 30, context: context)
        viewModel.addCompletion(for: habit, amount: 30, context: context) // only 20 remaining
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 50)
        #expect(viewModel.isCompleted(habit: habit))
    }

    @Test("addCompletion with zero does nothing")
    @MainActor
    func addCompletionZero() throws {
        let context = try makeContext()
        let habit = Habit(name: "Test", timesToComplete: 5)
        context.insert(habit)
        try context.save()

        viewModel.addCompletion(for: habit, amount: 0, context: context)
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 0)
    }

    @Test("deleteHabit tombstones the habit")
    @MainActor
    func deleteHabit() throws {
        let context = try makeContext()
        let habit = Habit(name: "Delete Me")
        context.insert(habit)
        try context.save()

        viewModel.deleteHabit(habit, context: context)
        try context.save()

        let descriptor = FetchDescriptor<Habit>()
        let remaining = try context.fetch(descriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.syncDeletedAt != nil)
        #expect(remaining.first?.syncNeedsPush == true)
    }

    @Test("Weekly habit: completion on Monday counts all week")
    @MainActor
    func weeklyCompletionPersists() throws {
        let context = try makeContext()
        let habit = Habit(name: "Review", frequency: .weekly, timesToComplete: 1)
        context.insert(habit)

        let now = Date.now
        let periodStart = DateHelpers.periodStart(for: now, frequency: .weekly)
        let completion = HabitCompletion(date: periodStart, count: 1, habit: habit)
        context.insert(completion)
        try context.save()

        #expect(viewModel.isCompleted(habit: habit))
    }

    @Test("Counter habit tracks progress accurately")
    @MainActor
    func counterProgress() throws {
        let context = try makeContext()
        let habit = Habit(name: "Water glasses", frequency: .daily, timesToComplete: 8)
        context.insert(habit)
        try context.save()

        for _ in 1...5 {
            viewModel.incrementCompletion(for: habit, context: context)
        }
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 5)
        #expect(!viewModel.isCompleted(habit: habit))

        for _ in 1...3 {
            viewModel.incrementCompletion(for: habit, context: context)
        }
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 8)
        #expect(viewModel.isCompleted(habit: habit))
    }

    @Test("Counter habit row tap increments by one")
    @MainActor
    func counterTapIncrements() throws {
        let context = try makeContext()
        let habit = Habit(name: "Pushups", timesToComplete: 5)
        context.insert(habit)
        try context.save()

        viewModel.logHabitTap(for: habit, context: context)
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 1)
    }

    // MARK: - Toggle completion

    @Test("Toggle on: creates completion for uncompleted habit")
    @MainActor
    func toggleOn() throws {
        let context = try makeContext()
        let habit = Habit(name: "Meditate", timesToComplete: 1)
        context.insert(habit)
        try context.save()

        #expect(!viewModel.isCompleted(habit: habit))
        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()

        #expect(viewModel.isCompleted(habit: habit))
        #expect(viewModel.completionCount(for: habit) == 1)
    }

    @Test("Toggle off: removes completion for completed habit")
    @MainActor
    func toggleOff() throws {
        let context = try makeContext()
        let habit = Habit(name: "Meditate", timesToComplete: 1)
        context.insert(habit)
        let completion = HabitCompletion(date: .now, count: 1, habit: habit)
        context.insert(completion)
        try context.save()

        #expect(viewModel.isCompleted(habit: habit))
        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()

        #expect(!viewModel.isCompleted(habit: habit))
        #expect(viewModel.completionCount(for: habit) == 0)
    }

    @Test("Toggle twice returns to original state")
    @MainActor
    func toggleRoundTrip() throws {
        let context = try makeContext()
        let habit = Habit(name: "Yoga", timesToComplete: 1)
        context.insert(habit)
        try context.save()

        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()
        #expect(viewModel.isCompleted(habit: habit))

        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()
        #expect(!viewModel.isCompleted(habit: habit))
    }

    @Test("Toggle three times: off → on → off → on works")
    @MainActor
    func toggleTripleRoundTrip() throws {
        let context = try makeContext()
        let habit = Habit(name: "Run", timesToComplete: 1)
        context.insert(habit)
        try context.save()

        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()
        #expect(viewModel.isCompleted(habit: habit))

        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()
        #expect(!viewModel.isCompleted(habit: habit))

        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()
        #expect(viewModel.isCompleted(habit: habit))
    }

    @Test("Toggling multiple habits does not interfere")
    @MainActor
    func toggleMultipleHabits() throws {
        let context = try makeContext()
        let habitA = Habit(name: "A", timesToComplete: 1)
        let habitB = Habit(name: "B", timesToComplete: 1)
        context.insert(habitA)
        context.insert(habitB)
        try context.save()

        viewModel.toggleCompletion(for: habitA, context: context)
        try context.save()
        #expect(viewModel.isCompleted(habit: habitA))

        viewModel.toggleCompletion(for: habitB, context: context)
        try context.save()
        #expect(viewModel.isCompleted(habit: habitB))

        viewModel.toggleCompletion(for: habitA, context: context)
        try context.save()
        #expect(!viewModel.isCompleted(habit: habitA))
        #expect(viewModel.isCompleted(habit: habitB))

        viewModel.toggleCompletion(for: habitA, context: context)
        try context.save()
        #expect(viewModel.isCompleted(habit: habitA))
        #expect(viewModel.isCompleted(habit: habitB))
    }

    @Test("Widget snapshot reflects habit progress")
    @MainActor
    func widgetSnapshotReflectsProgress() throws {
        let context = try makeContext()
        let habit = Habit(name: "Read", timesToComplete: 3)
        context.insert(habit)
        viewModel.addCompletion(for: habit, amount: 2, context: context)
        try context.save()

        let snapshot = HabitWidgetSyncService.makeSnapshot(habits: [habit])
        let item = try #require(snapshot.habits.first)

        #expect(item.name == "Read")
        #expect(item.completionCount == 2)
        #expect(item.timesToComplete == 3)
        #expect(!item.isCompleted)
    }

    @Test("Widget snapshot handles completed custom habit")
    @MainActor
    func widgetSnapshotHandlesCompletedCustomHabit() throws {
        let context = try makeContext()
        let habit = Habit(
            name: "Polla",
            frequency: .custom,
            customIntervalValue: 2,
            customIntervalUnit: .days,
            startDate: .now
        )
        context.insert(habit)
        viewModel.toggleCompletion(for: habit, context: context)
        try context.save()

        let snapshot = HabitWidgetSyncService.makeSnapshot(habits: [habit])
        let item = try #require(snapshot.habits.first)

        #expect(item.completionCount == 1)
        #expect(item.isCompleted)
    }

    @Test("Widget item recalculates daily progress for the requested date")
    @MainActor
    func widgetItemRecalculatesDailyProgress() throws {
        let context = try makeContext()
        let dayOne = makeDate(2026, 4, 27, hour: 10)
        let dayTwo = makeDate(2026, 4, 28, hour: 10)
        let habit = Habit(name: "Read", frequency: .daily, startDate: dayOne)
        context.insert(habit)
        context.insert(HabitCompletion(date: dayOne, count: 1, habit: habit))
        try context.save()

        let item = HabitWidgetSyncService.widgetItem(for: habit, date: dayOne)

        #expect(item.completionCount == 1)
        #expect(item.isCompleted)
        #expect(item.completionCount(on: dayTwo) == 0)
        #expect(!item.isCompleted(on: dayTwo))
    }

    @Test("Widget item treats custom interval off days as day off")
    @MainActor
    func widgetItemTreatsCustomIntervalOffDaysAsDayOff() throws {
        let context = try makeContext()
        let dayOne = makeDate(2026, 4, 27, hour: 10)
        let dayOff = makeDate(2026, 4, 28, hour: 10)
        let nextDueDay = makeDate(2026, 4, 29, hour: 10)
        let habit = Habit(
            name: "Stretch",
            frequency: .custom,
            customIntervalValue: 2,
            customIntervalUnit: .days,
            startDate: dayOne
        )
        context.insert(habit)
        context.insert(HabitCompletion(date: dayOne, count: 1, habit: habit))
        try context.save()

        let item = HabitWidgetSyncService.widgetItem(for: habit, date: dayOne)

        #expect(item.isScheduled(on: dayOne))
        #expect(item.completionCount(on: dayOne) == 1)
        #expect(item.isCompleted(on: dayOne))
        #expect(!item.isScheduled(on: dayOff))
        #expect(item.completionCount(on: dayOff) == 0)
        #expect(!item.isCompleted(on: dayOff))
        #expect(item.isScheduled(on: nextDueDay))
        #expect(item.completionCount(on: nextDueDay) == 0)
        #expect(!item.isCompleted(on: nextDueDay))
    }

    @Test("Widget snapshot streak skips custom interval off days")
    @MainActor
    func widgetSnapshotStreakSkipsOffDays() throws {
        let context = try makeContext()
        let dayOne = makeDate(2026, 4, 27, hour: 10)
        let dayOff = makeDate(2026, 4, 28, hour: 10)
        let habit = Habit(
            name: "Stretch",
            frequency: .custom,
            customIntervalValue: 2,
            customIntervalUnit: .days,
            startDate: dayOne
        )
        context.insert(habit)
        context.insert(HabitCompletion(date: dayOne, count: 1, habit: habit))
        try context.save()

        let item = HabitWidgetSyncService.widgetItem(for: habit, date: dayOff)

        #expect(item.streakDays == 1)
        #expect(item.streakDays(endingAt: dayOff) == 1)
    }

    // MARK: - Clear completion

    @Test("Clear removes all completions for current period")
    @MainActor
    func clearCompletion() throws {
        let context = try makeContext()
        let habit = Habit(name: "Pushups", timesToComplete: 50)
        context.insert(habit)
        try context.save()

        viewModel.addCompletion(for: habit, amount: 30, context: context)
        try context.save()
        #expect(viewModel.completionCount(for: habit) == 30)

        viewModel.clearCompletion(for: habit, context: context)
        try context.save()
        #expect(viewModel.completionCount(for: habit) == 0)
    }

    @Test("Clear does nothing when no completions exist")
    @MainActor
    func clearNoOp() throws {
        let context = try makeContext()
        let habit = Habit(name: "Test", timesToComplete: 5)
        context.insert(habit)
        try context.save()

        viewModel.clearCompletion(for: habit, context: context)
        try context.save()
        #expect(viewModel.completionCount(for: habit) == 0)
    }

    @Test("Clear does not affect other periods")
    @MainActor
    func clearOnlyCurrentPeriod() throws {
        let context = try makeContext()
        let habit = Habit(name: "Read", frequency: .daily, timesToComplete: 1)
        context.insert(habit)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let oldCompletion = HabitCompletion(date: yesterday, count: 1, habit: habit)
        context.insert(oldCompletion)

        let todayCompletion = HabitCompletion(date: .now, count: 1, habit: habit)
        context.insert(todayCompletion)
        try context.save()

        viewModel.clearCompletion(for: habit, context: context)
        try context.save()

        #expect(viewModel.completionCount(for: habit) == 0)
        #expect(viewModel.completionCount(for: habit, on: yesterday) == 1)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}

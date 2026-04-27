import Testing
import Foundation
import SwiftData
@testable import Habits

@Suite("HabitListViewModel")
struct HabitListViewModelTests {
    let viewModel = HabitListViewModel()

    // MARK: - Completion counting

    @Test("Completion count is zero with no completions")
    func zeroCompletions() {
        let habit = Habit(name: "Test")
        #expect(viewModel.completionCount(for: habit) == 0)
    }

    @Test("Completion count sums completions in current period")
    func sumsCurrentPeriod() {
        let habit = Habit(name: "Pushups", timesToComplete: 50)
        let now = Date.now
        let completion1 = HabitCompletion(date: now, count: 20, habit: habit)
        let completion2 = HabitCompletion(date: now, count: 15, habit: habit)
        habit.completions = [completion1, completion2]

        #expect(viewModel.completionCount(for: habit) == 35)
    }

    @Test("Completion count ignores completions from other periods")
    func ignoresOtherPeriods() {
        let habit = Habit(name: "Read", frequency: .daily, timesToComplete: 1)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let completion = HabitCompletion(date: yesterday, count: 1, habit: habit)
        habit.completions = [completion]

        #expect(viewModel.completionCount(for: habit) == 0)
    }

    @Test("Weekly completion counts within the same week")
    func weeklyCompletion() {
        let habit = Habit(name: "Gym", frequency: .weekly, timesToComplete: 3)
        let now = Date.now
        let periodStart = DateHelpers.periodStart(for: now, frequency: .weekly)
        let completion = HabitCompletion(date: periodStart, count: 2, habit: habit)
        habit.completions = [completion]

        #expect(viewModel.completionCount(for: habit) == 2)
    }

    // MARK: - isCompleted

    @Test("Not completed when count < target")
    func notCompleted() {
        let habit = Habit(name: "Test", timesToComplete: 5)
        let completion = HabitCompletion(date: .now, count: 3, habit: habit)
        habit.completions = [completion]

        #expect(!viewModel.isCompleted(habit: habit))
    }

    @Test("Completed when count == target")
    func completedExact() {
        let habit = Habit(name: "Test", timesToComplete: 3)
        let completion = HabitCompletion(date: .now, count: 3, habit: habit)
        habit.completions = [completion]

        #expect(viewModel.isCompleted(habit: habit))
    }

    @Test("Completed when count > target")
    func completedOver() {
        let habit = Habit(name: "Test", timesToComplete: 3)
        let completion = HabitCompletion(date: .now, count: 5, habit: habit)
        habit.completions = [completion]

        #expect(viewModel.isCompleted(habit: habit))
    }

    @Test("Simple habit completed with single completion")
    func simpleHabitCompleted() {
        let habit = Habit(name: "Meditate", timesToComplete: 1)
        let completion = HabitCompletion(date: .now, count: 1, habit: habit)
        habit.completions = [completion]

        #expect(viewModel.isCompleted(habit: habit))
    }

    // MARK: - Due dates

    @Test("Habit is due today when schedule matches")
    func dueTodayWhenScheduleMatches() {
        let today = makeDate(2026, 4, 27)
        let habit = Habit(name: "Review", frequency: .weekly, startDate: today)
        #expect(viewModel.isDueToday(habit, on: today))
    }

    @Test("Habit is not due today when scheduled for later")
    func notDueTodayWhenScheduledForLater() {
        let today = makeDate(2026, 4, 27)
        let startDate = makeDate(2026, 4, 29)
        let habit = Habit(name: "Review", frequency: .weekly, startDate: startDate)
        #expect(!viewModel.isDueToday(habit, on: today))
        #expect(viewModel.nextDueDate(for: habit, on: today) == startDate)
    }

    // MARK: - Frequency labels

    @Test("Daily label")
    func dailyLabel() {
        let habit = Habit(name: "Test", frequency: .daily)
        #expect(viewModel.frequencyLabel(for: habit) == "Daily")
    }

    @Test("Weekly label")
    func weeklyLabel() {
        let habit = Habit(name: "Test", frequency: .weekly)
        #expect(viewModel.frequencyLabel(for: habit) == "Weekly")
    }

    @Test("Monthly label")
    func monthlyLabel() {
        let habit = Habit(name: "Test", frequency: .monthly)
        #expect(viewModel.frequencyLabel(for: habit) == "Monthly")
    }

    @Test("Yearly label")
    func yearlyLabel() {
        let habit = Habit(name: "Test", frequency: .yearly)
        #expect(viewModel.frequencyLabel(for: habit) == "Yearly")
    }

    @Test("Custom label with days")
    func customDaysLabel() {
        let habit = Habit(name: "Test", frequency: .custom, customIntervalValue: 3, customIntervalUnit: .days)
        #expect(viewModel.frequencyLabel(for: habit) == "Every 3 days")
    }

    @Test("Custom label singularizes one day")
    func customSingularDayLabel() {
        let habit = Habit(name: "Test", frequency: .custom, customIntervalValue: 1, customIntervalUnit: .days)
        #expect(viewModel.frequencyLabel(for: habit) == "Every 1 day")
    }

    @Test("Custom label with weeks")
    func customWeeksLabel() {
        let habit = Habit(name: "Test", frequency: .custom, customIntervalValue: 2, customIntervalUnit: .weeks)
        #expect(viewModel.frequencyLabel(for: habit) == "Every 2 weeks")
    }

    @Test("Custom label with months")
    func customMonthsLabel() {
        let habit = Habit(name: "Test", frequency: .custom, customIntervalValue: 6, customIntervalUnit: .months)
        #expect(viewModel.frequencyLabel(for: habit) == "Every 6 months")
    }

    @Test("Custom label with nil values uses defaults")
    func customNilLabel() {
        let habit = Habit(name: "Test", frequency: .custom)
        #expect(viewModel.frequencyLabel(for: habit) == "Every 1 day")
    }

    @Test("Schedule label uses today")
    func scheduleLabelToday() {
        let today = makeDate(2026, 4, 27)
        let habit = Habit(name: "Test", frequency: .daily, startDate: today)
        #expect(viewModel.scheduleLabel(for: habit, on: today) == "Today")
    }

    @Test("Schedule label uses tomorrow")
    func scheduleLabelTomorrow() {
        let today = makeDate(2026, 4, 27)
        let habit = Habit(name: "Test", frequency: .daily, startDate: makeDate(2026, 4, 28))
        #expect(viewModel.scheduleLabel(for: habit, on: today) == "Tomorrow")
    }

    @Test("Schedule label uses abbreviated weekday within a week")
    func scheduleLabelWeekday() {
        let today = makeDate(2026, 4, 27)
        let habit = Habit(name: "Test", frequency: .weekly, startDate: makeDate(2026, 4, 29))
        #expect(viewModel.scheduleLabel(for: habit, on: today) == "Wed")
    }

    @Test("Schedule label uses abbreviated month and day after a week")
    func scheduleLabelMonthDay() {
        let today = makeDate(2026, 4, 27)
        let startDate = makeDate(2026, 5, 12)
        let habit = Habit(name: "Test", frequency: .monthly, startDate: startDate)
        #expect(viewModel.scheduleLabel(for: habit, on: today) == startDate.formatted(.dateTime.month(.abbreviated).day()))
    }

    // MARK: - State

    @Test("Initial state has no sheet showing")
    func initialState() {
        let vm = HabitListViewModel()
        #expect(!vm.showingAddSheet)
        #expect(vm.habitToEdit == nil)
        #expect(vm.habitToDelete == nil)
        #expect(!vm.showingDeleteConfirmation)
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

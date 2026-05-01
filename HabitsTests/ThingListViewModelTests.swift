import Testing
import Foundation
import SwiftData
@testable import Habits

@Suite("ThingListViewModel")
@MainActor
struct ThingListViewModelTests {
    let viewModel = ThingListViewModel()

    @Test("Incomplete overdue things are visible in Today")
    func incompleteOverdueShowsToday() {
        let today = makeDate(2026, 4, 28)
        let yesterday = makeDate(2026, 4, 27)
        let thing = Thing(title: "Pay bill", dueDate: yesterday)

        #expect(viewModel.isVisible(thing, on: today))
        #expect(viewModel.todaysThings(from: [thing], on: today).map(\.title) == ["Pay bill"])
        #expect(viewModel.laterThings(from: [thing], on: today).isEmpty)
    }

    @Test("Completed overdue thing remains visible when completed today")
    func completedOverdueTodayRemainsVisible() {
        let today = makeDate(2026, 4, 28, hour: 10)
        let yesterday = makeDate(2026, 4, 27)
        let thing = Thing(title: "Submit form", dueDate: yesterday, isCompleted: true, completedAt: today)

        #expect(viewModel.isVisible(thing, on: today))
        #expect(viewModel.todaysThings(from: [thing], on: today).map(\.title) == ["Submit form"])
    }

    @Test("Completed overdue thing is hidden after completion day")
    func completedOverdueHiddenTomorrow() {
        let today = makeDate(2026, 4, 28, hour: 10)
        let tomorrow = makeDate(2026, 4, 29, hour: 10)
        let yesterday = makeDate(2026, 4, 27)
        let thing = Thing(title: "Submit form", dueDate: yesterday, isCompleted: true, completedAt: today)

        #expect(!viewModel.isVisible(thing, on: tomorrow))
        #expect(viewModel.visibleThings(from: [thing], on: tomorrow).isEmpty)
    }

    @Test("Completed today thing stays visible today")
    func completedDueTodayStaysVisible() {
        let today = makeDate(2026, 4, 28, hour: 10)
        let thing = Thing(title: "Call Alex", dueDate: today, isCompleted: true, completedAt: today)

        #expect(viewModel.isVisible(thing, on: today))
        #expect(viewModel.todaysThings(from: [thing], on: today).map(\.title) == ["Call Alex"])
    }

    @Test("Future things show in Later")
    func futureThingShowsLater() {
        let today = makeDate(2026, 4, 28)
        let nextWeek = makeDate(2026, 5, 5)
        let thing = Thing(title: "Book train", dueDate: nextWeek)

        #expect(viewModel.todaysThings(from: [thing], on: today).isEmpty)
        #expect(viewModel.laterThings(from: [thing], on: today).map(\.title) == ["Book train"])
    }

    @Test("Open today count excludes future things")
    func openTodayCountExcludesFutureThings() {
        let today = makeDate(2026, 4, 28)
        let yesterday = Thing(title: "Late", dueDate: makeDate(2026, 4, 27))
        let dueToday = Thing(title: "Today", dueDate: today)
        let completedToday = Thing(title: "Done", dueDate: today, isCompleted: true, completedAt: today)
        let future = Thing(title: "Later", dueDate: makeDate(2026, 4, 29))

        #expect(viewModel.openTodayThingCount(from: [yesterday, dueToday, completedToday, future], on: today) == 2)
    }

    @Test("Completed things group by completion day descending")
    func completedThingSectionsGroupByCompletionDay() {
        let today = makeDate(2026, 4, 28, hour: 12)
        let yesterdayMorning = makeDate(2026, 4, 27, hour: 8)
        let yesterdayEvening = makeDate(2026, 4, 27, hour: 18)
        let completedToday = Thing(title: "Send invoice", dueDate: today, isCompleted: true, completedAt: today)
        let completedYesterdayLater = Thing(title: "Call Sam", dueDate: yesterdayMorning, isCompleted: true, completedAt: yesterdayEvening)
        let completedYesterdayEarlier = Thing(title: "Buy tape", dueDate: yesterdayMorning, isCompleted: true, completedAt: yesterdayMorning)
        let incomplete = Thing(title: "Still open", dueDate: today)
        let deleted = Thing(title: "Deleted", dueDate: today, isCompleted: true, completedAt: today, syncDeletedAt: today)

        let sections = viewModel.completedThingSections(
            from: [completedYesterdayEarlier, incomplete, completedToday, deleted, completedYesterdayLater],
            on: today,
            locale: Locale(identifier: "en_US")
        )

        #expect(sections.map(\.title) == ["Today", "Yesterday"])
        #expect(sections[0].things.map(\.title) == ["Send invoice"])
        #expect(sections[1].things.map(\.title) == ["Call Sam", "Buy tape"])
    }

    @Test("Future things cannot toggle completion before due day")
    @MainActor
    func futureThingCannotToggleBeforeDueDay() throws {
        let context = try makeContext()
        let today = makeDate(2026, 4, 28, hour: 9)
        let tomorrow = makeDate(2026, 4, 29)
        let thing = Thing(title: "Pack", dueDate: tomorrow)
        context.insert(thing)
        try context.save()

        #expect(!viewModel.allowsCompletionToggle(thing, on: today))

        viewModel.toggleCompletion(for: thing, context: context, date: today)

        #expect(!thing.isCompleted)
        #expect(thing.completedAt == nil)
    }

    @Test("Things can toggle completion on or after due day")
    func currentAndOverdueThingsCanToggle() {
        let today = makeDate(2026, 4, 28)
        let yesterday = makeDate(2026, 4, 27)

        #expect(viewModel.allowsCompletionToggle(Thing(title: "Today", dueDate: today), on: today))
        #expect(viewModel.allowsCompletionToggle(Thing(title: "Late", dueDate: yesterday), on: today))
    }

    @Test("Things sort by due date then title")
    func sortOrder() {
        let today = makeDate(2026, 4, 28)
        let tomorrow = makeDate(2026, 4, 29)
        let b = Thing(title: "Beta", dueDate: tomorrow)
        let a = Thing(title: "Alpha", dueDate: tomorrow)
        let urgent = Thing(title: "Zeta", dueDate: today)

        #expect(viewModel.visibleThings(from: [b, a, urgent], on: today).map(\.title) == ["Zeta", "Alpha", "Beta"])
    }

    @Test("Due labels use relative and formatted dates")
    func dueLabels() {
        let today = makeDate(2026, 4, 28)
        let yesterday = Thing(title: "Late", dueDate: makeDate(2026, 4, 27))
        let tomorrow = Thing(title: "Soon", dueDate: makeDate(2026, 4, 29))
        let future = Thing(title: "Later", dueDate: makeDate(2026, 5, 5))
        let nextYear = Thing(title: "Much later", dueDate: makeDate(2027, 5, 5))

        #expect(viewModel.dueLabel(for: yesterday, on: today, locale: Locale(identifier: "en_US")) == "Due yesterday")
        #expect(viewModel.dueLabel(for: Thing(title: "Now", dueDate: today), on: today, locale: Locale(identifier: "en_US")) == "Today")
        #expect(viewModel.dueLabel(for: tomorrow, on: today, locale: Locale(identifier: "en_US")) == "Tomorrow")
        #expect(viewModel.dueLabel(for: future, on: today, locale: Locale(identifier: "en_US")) == "May 5")
        #expect(viewModel.dueLabel(for: nextYear, on: today, locale: Locale(identifier: "en_US")) == "May 5, 2027")
    }

    @Test("Due labels format dates with supplied locale")
    func dueLabelsUseLocale() {
        let today = makeDate(2026, 4, 28)
        let future = Thing(title: "Later", dueDate: makeDate(2026, 5, 5))

        let label = viewModel.dueLabel(for: future, on: today, locale: Locale(identifier: "es_ES"))

        #expect(label != "May 5")
        #expect(label.contains("5"))
    }

    @Test("Injected date updates midnight rollover visibility")
    func injectedDateSupportsMidnightRollover() {
        let today = makeDate(2026, 4, 28, hour: 23)
        let tomorrow = makeDate(2026, 4, 29, hour: 1)
        let thing = Thing(title: "Finish notes", dueDate: today, isCompleted: true, completedAt: today)

        #expect(viewModel.isVisible(thing, on: today))
        #expect(!viewModel.isVisible(thing, on: tomorrow))
    }

    @Test("Toggle completion stamps and clears completedAt")
    @MainActor
    func toggleCompletion() throws {
        let context = try makeContext()
        let now = makeDate(2026, 4, 28, hour: 9)
        let thing = Thing(title: "Pack", dueDate: now)
        context.insert(thing)
        try context.save()

        viewModel.toggleCompletion(for: thing, context: context, date: now)
        #expect(thing.isCompleted)
        #expect(thing.completedAt == now)
        #expect(thing.syncCompletionUpdatedAt != nil)

        viewModel.toggleCompletion(for: thing, context: context, date: now)
        #expect(!thing.isCompleted)
        #expect(thing.completedAt == nil)
    }

    @Test("Move to tomorrow updates due date and clears completion")
    @MainActor
    func moveToTomorrow() throws {
        let context = try makeContext()
        let today = makeDate(2026, 4, 28, hour: 9)
        let tomorrow = makeDate(2026, 4, 29)
        let thing = Thing(title: "Pack", dueDate: today, isCompleted: true, completedAt: today)
        context.insert(thing)
        try context.save()

        viewModel.moveToTomorrow(thing, context: context, date: today)

        #expect(thing.dueDate == tomorrow)
        #expect(!thing.isCompleted)
        #expect(thing.completedAt == nil)
        #expect(thing.syncDueDateUpdatedAt != nil)
        #expect(thing.syncCompletionUpdatedAt != nil)
        #expect(viewModel.laterThings(from: [thing], on: today).map(\.title) == ["Pack"])
    }

    @Test("Move to today updates later thing due date and clears completion")
    @MainActor
    func moveToToday() throws {
        let context = try makeContext()
        let today = makeDate(2026, 4, 28, hour: 9)
        let tomorrow = makeDate(2026, 4, 29)
        let thing = Thing(title: "Pack", dueDate: tomorrow, isCompleted: true, completedAt: tomorrow)
        context.insert(thing)
        try context.save()

        #expect(viewModel.isLater(thing, on: today))

        viewModel.moveToToday(thing, context: context, date: today)

        #expect(thing.dueDate == makeDate(2026, 4, 28))
        #expect(!thing.isCompleted)
        #expect(thing.completedAt == nil)
        #expect(viewModel.todaysThings(from: [thing], on: today).map(\.title) == ["Pack"])
        #expect(!viewModel.isLater(thing, on: today))
    }

    @Test("Delete tombstones thing and hides it from visible lists")
    @MainActor
    func deleteThing() throws {
        let context = try makeContext()
        let thing = Thing(title: "Delete me")
        context.insert(thing)
        try context.save()

        viewModel.deleteThing(thing, context: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Thing>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.syncDeletedAt != nil)
        #expect(remaining.first?.syncDeletionUpdatedAt != nil)
        #expect(remaining.first?.syncNeedsPush == true)
        #expect(viewModel.visibleThings(from: remaining).isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Habit.self, HabitCompletion.self, Thing.self, configurations: config)
        return ModelContext(container)
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

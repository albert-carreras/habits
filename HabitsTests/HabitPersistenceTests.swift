import Testing
import Foundation
import SwiftData
@testable import Habits

@Suite("Habit Persistence")
struct HabitPersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Habit.self, HabitCompletion.self, configurations: config)
    }

    @Test("Insert and fetch a habit")
    @MainActor
    func insertAndFetch() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let habit = Habit(name: "Exercise", frequency: .daily, timesToComplete: 1)
        context.insert(habit)
        try context.save()

        let descriptor = FetchDescriptor<Habit>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Exercise")
        #expect(fetched.first?.frequency == .daily)
    }

    @Test("Delete a habit")
    @MainActor
    func deleteHabit() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let habit = Habit(name: "Yoga")
        context.insert(habit)
        try context.save()

        context.delete(habit)
        try context.save()

        let descriptor = FetchDescriptor<Habit>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.isEmpty)
    }

    @Test("Update habit properties")
    @MainActor
    func updateHabit() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let habit = Habit(name: "Read", frequency: .daily, timesToComplete: 1)
        context.insert(habit)
        try context.save()

        habit.name = "Read Books"
        habit.frequency = .weekly
        habit.timesToComplete = 3
        try context.save()

        let descriptor = FetchDescriptor<Habit>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.first?.name == "Read Books")
        #expect(fetched.first?.frequency == .weekly)
        #expect(fetched.first?.timesToComplete == 3)
    }

    @Test("Insert completion linked to habit")
    @MainActor
    func insertCompletion() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let habit = Habit(name: "Pushups", timesToComplete: 50)
        context.insert(habit)

        let completion = HabitCompletion(date: .now, count: 25, habit: habit)
        context.insert(completion)
        try context.save()

        let descriptor = FetchDescriptor<Habit>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.first?.completions.count == 1)
        #expect(fetched.first?.completions.first?.count == 25)
    }

    @Test("Cascade delete removes completions")
    @MainActor
    func cascadeDelete() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let habit = Habit(name: "Test")
        context.insert(habit)

        let c1 = HabitCompletion(date: .now, count: 1, habit: habit)
        let c2 = HabitCompletion(date: .now, count: 1, habit: habit)
        context.insert(c1)
        context.insert(c2)
        try context.save()

        context.delete(habit)
        try context.save()

        let completionDescriptor = FetchDescriptor<HabitCompletion>()
        let completions = try context.fetch(completionDescriptor)
        #expect(completions.isEmpty)
    }

    @Test("Multiple habits coexist")
    @MainActor
    func multipleHabits() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let h1 = Habit(name: "Alpha")
        let h2 = Habit(name: "Beta")
        let h3 = Habit(name: "Gamma")
        context.insert(h1)
        context.insert(h2)
        context.insert(h3)
        try context.save()

        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.name)])
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 3)
        #expect(fetched[0].name == "Alpha")
        #expect(fetched[1].name == "Beta")
        #expect(fetched[2].name == "Gamma")
    }

    @Test("Multiple completions per habit")
    @MainActor
    func multipleCompletions() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let habit = Habit(name: "Water", timesToComplete: 8)
        context.insert(habit)

        for i in 1...5 {
            let c = HabitCompletion(date: .now, count: i, habit: habit)
            context.insert(c)
        }
        try context.save()

        let descriptor = FetchDescriptor<Habit>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.first?.completions.count == 5)
        let total = fetched.first?.completions.reduce(0) { $0 + $1.count } ?? 0
        #expect(total == 15)
    }

    @Test("Habit with all custom fields")
    @MainActor
    func allCustomFields() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let startDate = Date(timeIntervalSince1970: 1700000000)
        let habit = Habit(
            name: "Custom Habit",
            frequency: .custom,
            customIntervalValue: 14,
            customIntervalUnit: .days,
            timesToComplete: 100,
            startDate: startDate,
            notificationsEnabled: true
        )
        context.insert(habit)
        try context.save()

        let descriptor = FetchDescriptor<Habit>()
        let fetched = try context.fetch(descriptor).first!
        #expect(fetched.frequency == .custom)
        #expect(fetched.customIntervalValue == 14)
        #expect(fetched.customIntervalUnit == .days)
        #expect(fetched.timesToComplete == 100)
        #expect(fetched.startDate == startDate)
        #expect(fetched.notificationsEnabled == true)
    }
}

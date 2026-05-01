import Testing
import Foundation
import SwiftData
@testable import Habits

@Suite("Thing Persistence")
struct ThingPersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Habit.self, HabitCompletion.self, Thing.self, configurations: config)
    }

    @Test("Insert and fetch a thing")
    @MainActor
    func insertAndFetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let dueDate = makeDate(2026, 4, 28)

        context.insert(Thing(title: "Buy milk", dueDate: dueDate))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Thing>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Buy milk")
        #expect(fetched.first?.dueDate == dueDate)
        #expect(fetched.first?.isCompleted == false)
    }

    @Test("Update thing properties")
    @MainActor
    func updateThing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thing = Thing(title: "Draft")
        context.insert(thing)
        try context.save()

        let completedAt = makeDate(2026, 4, 28, hour: 11)
        thing.title = "Final"
        thing.dueDate = makeDate(2026, 4, 29)
        thing.isCompleted = true
        thing.completedAt = completedAt
        try context.save()

        let fetched = try #require(context.fetch(FetchDescriptor<Thing>()).first)
        #expect(fetched.title == "Final")
        #expect(fetched.dueDate == makeDate(2026, 4, 29))
        #expect(fetched.isCompleted)
        #expect(fetched.completedAt == completedAt)
    }

    @Test("Delete a thing")
    @MainActor
    func deleteThing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thing = Thing(title: "Delete")
        context.insert(thing)
        try context.save()

        context.delete(thing)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Thing>()).isEmpty)
    }

    @Test("Things sort by due date then title in fetch descriptor")
    @MainActor
    func fetchSort() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Thing(title: "Beta", dueDate: makeDate(2026, 4, 29)))
        context.insert(Thing(title: "Alpha", dueDate: makeDate(2026, 4, 29)))
        context.insert(Thing(title: "Zeta", dueDate: makeDate(2026, 4, 28)))
        try context.save()

        let descriptor = FetchDescriptor<Thing>(
            sortBy: [
                SortDescriptor(\.dueDate),
                SortDescriptor(\.title)
            ]
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.map(\.title) == ["Zeta", "Alpha", "Beta"])
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

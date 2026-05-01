import Testing
import Foundation
@testable import Habits

@Suite("Thing Model")
struct ThingModelTests {

    @Test("Default initializer sets expected values")
    func defaultInit() {
        let before = Date.now
        let thing = Thing(title: "Buy milk")
        let after = Date.now

        #expect(thing.title == "Buy milk")
        #expect(thing.dueDate >= Calendar.current.startOfDay(for: before))
        #expect(thing.dueDate <= after)
        #expect(!thing.isCompleted)
        #expect(thing.completedAt == nil)
    }

    @Test("Initializer normalizes due date to start of day")
    func normalizesDueDate() {
        let dueDate = makeDate(2026, 4, 28, hour: 16, minute: 45)
        let thing = Thing(title: "Renew passport", dueDate: dueDate)

        #expect(thing.dueDate == Calendar.current.startOfDay(for: dueDate))
    }

    @Test("Each thing gets a unique ID")
    func uniqueIDs() {
        let first = Thing(title: "A")
        let second = Thing(title: "B")

        #expect(first.id != second.id)
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

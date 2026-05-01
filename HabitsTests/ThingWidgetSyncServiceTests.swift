import Testing
import Foundation
@testable import Habits

@Suite("ThingWidgetSyncService")
struct ThingWidgetSyncServiceTests {
    @Test("Snapshot includes incomplete things sorted by due date then title")
    func snapshotSorting() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        let thingB = Thing(title: "B task", dueDate: today)
        let thingA = Thing(title: "A task", dueDate: today)
        let thingC = Thing(title: "C task", dueDate: tomorrow)

        let snapshot = ThingWidgetSyncService.makeSnapshot(things: [thingB, thingA, thingC], date: today)

        #expect(snapshot.things.count == 3)
        #expect(snapshot.things[0].title == "A task")
        #expect(snapshot.things[1].title == "B task")
        #expect(snapshot.things[2].title == "C task")
    }

    @Test("Snapshot excludes soft-deleted things")
    func excludesDeleted() {
        let thing = Thing(title: "Deleted", dueDate: .now, syncDeletedAt: .now)

        let snapshot = ThingWidgetSyncService.makeSnapshot(things: [thing])

        #expect(snapshot.things.isEmpty)
    }

    @Test("Snapshot hides completed past things unless completed today")
    func hidesCompletedPastThings() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let completedYesterday = Thing(title: "Old", dueDate: yesterday, isCompleted: true, completedAt: yesterday)
        let completedToday = Thing(title: "Fresh", dueDate: yesterday, isCompleted: true, completedAt: today)

        let snapshot = ThingWidgetSyncService.makeSnapshot(things: [completedYesterday, completedToday], date: today)

        #expect(snapshot.things.count == 1)
        #expect(snapshot.things[0].title == "Fresh")
    }

    @Test("Snapshot includes incomplete future things")
    func includesFutureThings() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let nextWeek = cal.date(byAdding: .day, value: 7, to: today)!

        let thing = Thing(title: "Future", dueDate: nextWeek)

        let snapshot = ThingWidgetSyncService.makeSnapshot(things: [thing], date: today)

        #expect(snapshot.things.count == 1)
        #expect(snapshot.things[0].title == "Future")
    }
}

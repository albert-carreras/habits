import WidgetKit
import SwiftUI

struct ThingWidgetEntry: TimelineEntry {
    let date: Date
    let things: [ThingWidgetItem]
}

struct ThingWidgetProvider: TimelineProvider {
    typealias Entry = ThingWidgetEntry

    func placeholder(in context: Context) -> ThingWidgetEntry {
        ThingWidgetEntry(
            date: .now,
            things: [
                ThingWidgetItem(id: UUID(), title: "Buy groceries", dueDate: .now, isCompleted: false),
                ThingWidgetItem(id: UUID(), title: "Call dentist", dueDate: .now, isCompleted: false),
                ThingWidgetItem(id: UUID(), title: "Reply to email", dueDate: .now, isCompleted: false),
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ThingWidgetEntry) -> Void) {
        completion(fetchEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThingWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = fetchEntry(date: now)
        let nextUpdate = nextRefreshDate(after: now)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry(date: Date) -> ThingWidgetEntry {
        let snapshot = ThingWidgetDataStore.loadSnapshot()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        let incomplete = snapshot.things
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let todayOrOverdue = incomplete.filter { calendar.startOfDay(for: $0.dueDate) <= today }
        let later = incomplete.filter { calendar.startOfDay(for: $0.dueDate) > today }
        let ordered = todayOrOverdue + later

        return ThingWidgetEntry(
            date: date,
            things: Array(ordered.prefix(3))
        )
    }

    private func nextRefreshDate(after date: Date) -> Date {
        let calendar = Calendar.current
        let thirtyMinutes = calendar.date(byAdding: .minute, value: 30, to: date) ?? date
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? thirtyMinutes
        return min(thirtyMinutes, nextMidnight)
    }
}

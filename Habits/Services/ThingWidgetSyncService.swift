import Foundation
import SwiftData
import WidgetKit

enum ThingWidgetSyncService {
    @discardableResult
    static func sync(context: ModelContext, date: Date = .now) -> Bool {
        let descriptor = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.dueDate), SortDescriptor(\.title)])
        guard let things = try? context.fetch(descriptor) else { return false }

        return sync(things: things.filter { $0.syncDeletedAt == nil }, date: date)
    }

    @discardableResult
    static func sync(things: [Thing], date: Date = .now) -> Bool {
        guard !AppEnvironment.disablesWidgetSync else { return true }

        let snapshot = makeSnapshot(things: things, date: date)
        do {
            try ThingWidgetDataStore.saveSnapshot(snapshot)
        } catch {
            #if DEBUG
            print("ThingWidgetSyncService failed to save snapshot: \(error)")
            #endif
            return false
        }
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    static func makeSnapshot(things: [Thing], date: Date = .now) -> ThingWidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        let visible = things
            .filter { $0.syncDeletedAt == nil }
            .filter { thing in
                guard thing.isCompleted else { return true }
                let dueDay = calendar.startOfDay(for: thing.dueDate)
                guard dueDay < today else { return true }
                guard let completedAt = thing.completedAt else { return false }
                return calendar.isDate(completedAt, inSameDayAs: today)
            }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        return ThingWidgetSnapshot(
            generatedAt: date,
            things: visible.map { ThingWidgetItem(id: $0.id, title: $0.title, dueDate: $0.dueDate, isCompleted: $0.isCompleted) }
        )
    }
}

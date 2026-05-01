import Foundation
import SwiftData

struct CompletedThingDaySection {
    let day: Date
    let title: String
    let things: [Thing]
}

@MainActor
final class ThingListViewModel {
    func visibleThings(from things: [Thing], on date: Date = .now, calendar: Calendar = .current) -> [Thing] {
        sortedThings(things.filter { $0.syncDeletedAt == nil && isVisible($0, on: date, calendar: calendar) })
    }

    func todaysThings(from things: [Thing], on date: Date = .now, calendar: Calendar = .current) -> [Thing] {
        let today = calendar.startOfDay(for: date)
        return visibleThings(from: things, on: date, calendar: calendar)
            .filter { calendar.startOfDay(for: $0.dueDate) <= today }
    }

    func laterThings(from things: [Thing], on date: Date = .now, calendar: Calendar = .current) -> [Thing] {
        let today = calendar.startOfDay(for: date)
        return visibleThings(from: things, on: date, calendar: calendar)
            .filter { calendar.startOfDay(for: $0.dueDate) > today }
    }

    func openTodayThingCount(from things: [Thing], on date: Date = .now, calendar: Calendar = .current) -> Int {
        todaysThings(from: things, on: date, calendar: calendar)
            .filter { !$0.isCompleted }
            .count
    }

    func completedThingSections(
        from things: [Thing],
        on date: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .current
    ) -> [CompletedThingDaySection] {
        let completed = completedThings(from: things, calendar: calendar)
        let grouped = Dictionary(grouping: completed) { thing in
            calendar.startOfDay(for: thing.completedAt ?? thing.dueDate)
        }

        return grouped.keys.sorted(by: >).map { day in
            CompletedThingDaySection(
                day: day,
                title: completedDayLabel(for: day, on: date, locale: locale, calendar: calendar),
                things: grouped[day] ?? []
            )
        }
    }

    func isVisible(_ thing: Thing, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard thing.isCompleted else { return true }

        let today = calendar.startOfDay(for: date)
        let dueDay = calendar.startOfDay(for: thing.dueDate)
        guard dueDay < today else { return true }

        guard let completedAt = thing.completedAt else { return false }
        return calendar.isDate(completedAt, inSameDayAs: today)
    }

    func isOverdue(_ thing: Thing, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        !thing.isCompleted && calendar.startOfDay(for: thing.dueDate) < calendar.startOfDay(for: date)
    }

    func allowsCompletionToggle(_ thing: Thing, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: thing.dueDate) <= calendar.startOfDay(for: date)
    }

    func isLater(_ thing: Thing, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: thing.dueDate) > calendar.startOfDay(for: date)
    }

    func toggleCompletion(for thing: Thing, context: ModelContext, date: Date = .now) {
        guard allowsCompletionToggle(thing, on: date) else { return }

        if thing.isCompleted {
            thing.isCompleted = false
            thing.completedAt = nil
        } else {
            thing.isCompleted = true
            thing.completedAt = date
        }
        markDirty(thing, fields: [.completion])

        save(context: context)
    }

    func moveToToday(_ thing: Thing, context: ModelContext, date: Date = .now, calendar: Calendar = .current) {
        move(thing, to: calendar.startOfDay(for: date), context: context)
    }

    func moveToTomorrow(_ thing: Thing, context: ModelContext, date: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        move(thing, to: tomorrow, context: context)
    }

    func deleteThing(_ thing: Thing, context: ModelContext) {
        markDirty(thing, deletedAt: .now)
        save(context: context)
    }

    func dueLabel(for thing: Thing, on date: Date = .now, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: date)
        let dueDay = calendar.startOfDay(for: thing.dueDate)

        if dueDay < today {
            return String(
                format: String(localized: "Due %@", comment: "Overdue thing date label"),
                relativeDayLabel(for: dueDay, relativeTo: today, locale: locale, calendar: calendar)
            )
        }

        if calendar.isDate(dueDay, inSameDayAs: today) {
            return String(localized: "Today", comment: "Thing due today label")
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(dueDay, inSameDayAs: tomorrow) {
            return relativeDayLabel(for: dueDay, relativeTo: today, locale: locale, calendar: calendar)
                .capitalized(with: locale)
        }

        if calendar.component(.year, from: dueDay) == calendar.component(.year, from: today) {
            return dueDay.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        }

        return dueDay.formatted(.dateTime.month(.abbreviated).day().year().locale(locale))
    }

    func completedDayLabel(
        for day: Date,
        on date: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .current
    ) -> String {
        let normalizedDay = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: date)

        if calendar.isDate(normalizedDay, inSameDayAs: today) {
            return String(localized: "Today", comment: "Completed things section for today")
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(normalizedDay, inSameDayAs: yesterday) {
            return String(localized: "Yesterday", comment: "Completed things section for yesterday")
        }

        if calendar.component(.year, from: normalizedDay) == calendar.component(.year, from: today) {
            return normalizedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(locale))
        }

        return normalizedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year().locale(locale))
    }

    private func sortedThings(_ things: [Thing]) -> [Thing] {
        things.sorted { lhs, rhs in
            if lhs.dueDate != rhs.dueDate {
                return lhs.dueDate < rhs.dueDate
            }

            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func completedThings(from things: [Thing], calendar: Calendar) -> [Thing] {
        things
            .filter { $0.syncDeletedAt == nil && $0.isCompleted && $0.completedAt != nil }
            .sorted { lhs, rhs in
                let lhsCompletedAt = lhs.completedAt ?? .distantPast
                let rhsCompletedAt = rhs.completedAt ?? .distantPast

                let lhsDay = calendar.startOfDay(for: lhsCompletedAt)
                let rhsDay = calendar.startOfDay(for: rhsCompletedAt)
                if lhsDay != rhsDay {
                    return lhsDay > rhsDay
                }

                if lhsCompletedAt != rhsCompletedAt {
                    return lhsCompletedAt > rhsCompletedAt
                }

                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func relativeDayLabel(for date: Date, relativeTo referenceDate: Date, locale: Locale, calendar: Calendar) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    private func move(_ thing: Thing, to dueDate: Date, context: ModelContext) {
        thing.dueDate = dueDate
        thing.isCompleted = false
        thing.completedAt = nil
        markDirty(thing, fields: [.dueDate, .completion])

        save(context: context)
    }

    private func markDirty(_ thing: Thing, deletedAt: Date? = nil, fields: ThingDirtyFields = []) {
        let now = Date.now
        thing.syncUpdatedAt = now
        thing.syncDeletedAt = deletedAt
        if deletedAt != nil {
            thing.syncDeletionUpdatedAt = now
        }
        if fields.contains(.title) {
            thing.syncTitleUpdatedAt = now
        }
        if fields.contains(.dueDate) {
            thing.syncDueDateUpdatedAt = now
        }
        if fields.contains(.completion) {
            thing.syncCompletionUpdatedAt = now
        }
        thing.syncNeedsPush = true
    }

    private func save(context: ModelContext) {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("ThingListViewModel failed to save context: \(error)")
            #endif
            return
        }
        SyncService.schedulePush(context: context)
        ThingWidgetSyncService.sync(context: context)
    }
}

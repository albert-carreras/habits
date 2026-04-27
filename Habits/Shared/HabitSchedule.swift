import Foundation

enum HabitSchedule {
    static func isScheduled(
        on date: Date,
        frequencyRawValue: String?,
        customValue: Int? = nil,
        customUnitRawValue: String? = nil,
        habitStart: Date?
    ) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let nextDate = nextScheduledDate(
            onOrAfter: day,
            frequencyRawValue: frequencyRawValue,
            customValue: customValue,
            customUnitRawValue: customUnitRawValue,
            habitStart: habitStart
        )
        return calendar.isDate(nextDate, inSameDayAs: day)
    }

    static func nextScheduledDate(
        onOrAfter date: Date,
        frequencyRawValue: String?,
        customValue: Int? = nil,
        customUnitRawValue: String? = nil,
        habitStart: Date?
    ) -> Date {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: date)
        guard let habitStart else { return target }

        let start = calendar.startOfDay(for: habitStart)
        guard target >= start else { return start }

        switch frequencyRawValue {
        case "Daily":
            return target
        case "Weekly":
            let daysSinceStart = calendar.dateComponents([.day], from: start, to: target).day ?? 0
            let daysUntilNext = (7 - (daysSinceStart % 7)) % 7
            return calendar.date(byAdding: .day, value: daysUntilNext, to: target) ?? target
        case "Monthly":
            return nextMonthlyDate(onOrAfter: target, start: start)
        case "Yearly":
            return nextYearlyDate(onOrAfter: target, start: start)
        case "Custom":
            let value = max(1, customValue ?? 1)
            let unitRawValue = customUnitRawValue ?? "Days"
            let periodStart = customPeriodStart(
                for: target,
                intervalValue: value,
                intervalUnitRawValue: unitRawValue,
                habitStart: start
            )
            if calendar.isDate(periodStart, inSameDayAs: target) {
                return periodStart
            }
            return periodEnd(
                for: periodStart,
                frequencyRawValue: "Custom",
                customValue: value,
                customUnitRawValue: unitRawValue
            )
        default:
            return target
        }
    }

    static func periodStart(
        for date: Date,
        frequencyRawValue: String?,
        customValue: Int? = nil,
        customUnitRawValue: String? = nil,
        habitStart: Date? = nil
    ) -> Date {
        let calendar = Calendar.current

        switch frequencyRawValue {
        case "Daily":
            return calendar.startOfDay(for: date)
        case "Weekly":
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        case "Monthly":
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        case "Yearly":
            let components = calendar.dateComponents([.year], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        case "Custom":
            guard let habitStart else { return calendar.startOfDay(for: date) }
            return customPeriodStart(
                for: date,
                intervalValue: customValue ?? 1,
                intervalUnitRawValue: customUnitRawValue,
                habitStart: habitStart
            )
        default:
            return calendar.startOfDay(for: date)
        }
    }

    static func periodEnd(
        for periodStart: Date,
        frequencyRawValue: String?,
        customValue: Int? = nil,
        customUnitRawValue: String? = nil
    ) -> Date {
        let calendar = Calendar.current

        switch frequencyRawValue {
        case "Daily":
            return calendar.date(byAdding: .day, value: 1, to: periodStart) ?? periodStart
        case "Weekly":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: periodStart) ?? periodStart
        case "Monthly":
            return calendar.date(byAdding: .month, value: 1, to: periodStart) ?? periodStart
        case "Yearly":
            return calendar.date(byAdding: .year, value: 1, to: periodStart) ?? periodStart
        case "Custom":
            return calendar.date(
                byAdding: calendarComponent(for: customUnitRawValue),
                value: max(1, customValue ?? 1),
                to: periodStart
            ) ?? periodStart
        default:
            return calendar.date(byAdding: .day, value: 1, to: periodStart) ?? periodStart
        }
    }

    private static func customPeriodStart(
        for date: Date,
        intervalValue: Int,
        intervalUnitRawValue: String?,
        habitStart: Date
    ) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: habitStart)
        let target = calendar.startOfDay(for: date)
        let intervalValue = max(1, intervalValue)
        let component = calendarComponent(for: intervalUnitRawValue)

        var periodStart = start
        while true {
            guard let nextPeriod = calendar.date(byAdding: component, value: intervalValue, to: periodStart) else { break }
            if nextPeriod > target { break }
            periodStart = nextPeriod
        }
        return periodStart
    }

    private static func calendarComponent(for unitRawValue: String?) -> Calendar.Component {
        switch unitRawValue {
        case "Weeks": .weekOfYear
        case "Months": .month
        default: .day
        }
    }

    private static func nextMonthlyDate(onOrAfter target: Date, start: Date) -> Date {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.day], from: start)
        let targetComponents = calendar.dateComponents([.year, .month], from: target)

        guard let year = targetComponents.year,
              let month = targetComponents.month,
              let day = startComponents.day else {
            return target
        }

        let thisMonth = clampedDate(year: year, month: month, day: day)
        if thisMonth >= target {
            return thisMonth
        }

        let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? target
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonthDate)
        return clampedDate(year: nextComponents.year ?? year, month: nextComponents.month ?? month, day: day)
    }

    private static func nextYearlyDate(onOrAfter target: Date, start: Date) -> Date {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.month, .day], from: start)
        let targetComponents = calendar.dateComponents([.year], from: target)

        guard let year = targetComponents.year,
              let month = startComponents.month,
              let day = startComponents.day else {
            return target
        }

        let thisYear = clampedDate(year: year, month: month, day: day)
        if thisYear >= target {
            return thisYear
        }

        return clampedDate(year: year + 1, month: month, day: day)
    }

    private static func clampedDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let firstOfMonth = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return calendar.date(from: components) ?? Date()
        }

        components.day = min(day, dayRange.count)
        return calendar.date(from: components) ?? firstOfMonth
    }
}

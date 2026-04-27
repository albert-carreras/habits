import Foundation

struct DateHelpers {
    static func isScheduled(on date: Date, frequency: HabitFrequency, customValue: Int? = nil, customUnit: CustomIntervalUnit? = nil, habitStart: Date) -> Bool {
        HabitSchedule.isScheduled(
            on: date,
            frequencyRawValue: frequency.rawValue,
            customValue: customValue,
            customUnitRawValue: customUnit?.rawValue,
            habitStart: habitStart
        )
    }

    static func nextScheduledDate(onOrAfter date: Date, frequency: HabitFrequency, customValue: Int? = nil, customUnit: CustomIntervalUnit? = nil, habitStart: Date) -> Date {
        HabitSchedule.nextScheduledDate(
            onOrAfter: date,
            frequencyRawValue: frequency.rawValue,
            customValue: customValue,
            customUnitRawValue: customUnit?.rawValue,
            habitStart: habitStart
        )
    }

    static func periodStart(for date: Date, frequency: HabitFrequency, customValue: Int? = nil, customUnit: CustomIntervalUnit? = nil, habitStart: Date? = nil) -> Date {
        HabitSchedule.periodStart(
            for: date,
            frequencyRawValue: frequency.rawValue,
            customValue: customValue,
            customUnitRawValue: customUnit?.rawValue,
            habitStart: habitStart
        )
    }

    static func periodEnd(for periodStart: Date, frequency: HabitFrequency, customValue: Int? = nil, customUnit: CustomIntervalUnit? = nil) -> Date {
        HabitSchedule.periodEnd(
            for: periodStart,
            frequencyRawValue: frequency.rawValue,
            customValue: customValue,
            customUnitRawValue: customUnit?.rawValue
        )
    }
}

import Testing
import Foundation
@testable import Habits

@Suite("DateHelpers")
struct DateHelpersTests {

    // MARK: - Daily

    @Test("Daily period start is start of day")
    func dailyPeriodStart() {
        let date = makeDate(2026, 4, 27, hour: 14, minute: 30)
        let result = DateHelpers.periodStart(for: date, frequency: .daily)
        let expected = makeDate(2026, 4, 27)
        #expect(result == expected)
    }

    @Test("Daily period end is next day")
    func dailyPeriodEnd() {
        let start = makeDate(2026, 4, 27)
        let result = DateHelpers.periodEnd(for: start, frequency: .daily)
        let expected = makeDate(2026, 4, 28)
        #expect(result == expected)
    }

    // MARK: - Weekly

    @Test("Weekly period start is start of week")
    func weeklyPeriodStart() {
        let wednesday = makeDate(2026, 4, 29)
        let result = DateHelpers.periodStart(for: wednesday, frequency: .weekly)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: wednesday)
        let expected = calendar.date(from: components)!
        #expect(result == expected)
    }

    @Test("Weekly period end is one week after start")
    func weeklyPeriodEnd() {
        let start = makeDate(2026, 4, 27)
        let weekStart = DateHelpers.periodStart(for: start, frequency: .weekly)
        let result = DateHelpers.periodEnd(for: weekStart, frequency: .weekly)
        let expected = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
        #expect(result == expected)
    }

    @Test("Weekly schedule repeats on start weekday")
    func weeklyScheduleRepeatsOnStartWeekday() {
        let habitStart = makeDate(2026, 4, 29)
        let monday = makeDate(2026, 5, 4)
        let result = DateHelpers.nextScheduledDate(onOrAfter: monday, frequency: .weekly, habitStart: habitStart)
        let expected = makeDate(2026, 5, 6)
        #expect(result == expected)
        #expect(!DateHelpers.isScheduled(on: monday, frequency: .weekly, habitStart: habitStart))
    }

    @Test("Weekly schedule is due on matching weekday")
    func weeklyScheduleDueOnMatchingWeekday() {
        let habitStart = makeDate(2026, 4, 29)
        let wednesday = makeDate(2026, 5, 6)
        #expect(DateHelpers.isScheduled(on: wednesday, frequency: .weekly, habitStart: habitStart))
    }

    // MARK: - Monthly

    @Test("Monthly period start is first of month")
    func monthlyPeriodStart() {
        let date = makeDate(2026, 4, 15)
        let result = DateHelpers.periodStart(for: date, frequency: .monthly)
        let expected = makeDate(2026, 4, 1)
        #expect(result == expected)
    }

    @Test("Monthly period end is first of next month")
    func monthlyPeriodEnd() {
        let start = makeDate(2026, 4, 1)
        let result = DateHelpers.periodEnd(for: start, frequency: .monthly)
        let expected = makeDate(2026, 5, 1)
        #expect(result == expected)
    }

    @Test("Monthly schedule clamps to last day of shorter month")
    func monthlyScheduleClampsShortMonth() {
        let habitStart = makeDate(2026, 1, 31)
        let february = makeDate(2026, 2, 1)
        let result = DateHelpers.nextScheduledDate(onOrAfter: february, frequency: .monthly, habitStart: habitStart)
        let expected = makeDate(2026, 2, 28)
        #expect(result == expected)
    }

    // MARK: - Yearly

    @Test("Yearly period start is Jan 1")
    func yearlyPeriodStart() {
        let date = makeDate(2026, 7, 15)
        let result = DateHelpers.periodStart(for: date, frequency: .yearly)
        let expected = makeDate(2026, 1, 1)
        #expect(result == expected)
    }

    @Test("Yearly period end is Jan 1 next year")
    func yearlyPeriodEnd() {
        let start = makeDate(2026, 1, 1)
        let result = DateHelpers.periodEnd(for: start, frequency: .yearly)
        let expected = makeDate(2027, 1, 1)
        #expect(result == expected)
    }

    // MARK: - Custom intervals

    @Test("Custom every 3 days: period start calculation")
    func customDaysPeriodStart() {
        let habitStart = makeDate(2026, 4, 1)
        let date = makeDate(2026, 4, 8) // 7 days in → period 3 (days 7-9)
        let result = DateHelpers.periodStart(for: date, frequency: .custom, customValue: 3, customUnit: .days, habitStart: habitStart)
        let expected = makeDate(2026, 4, 7)
        #expect(result == expected)
    }

    @Test("Custom every 2 weeks: period start calculation")
    func customWeeksPeriodStart() {
        let habitStart = makeDate(2026, 4, 1)
        let date = makeDate(2026, 4, 20) // 19 days in → second 2-week period
        let result = DateHelpers.periodStart(for: date, frequency: .custom, customValue: 2, customUnit: .weeks, habitStart: habitStart)
        let expected = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: makeDate(2026, 4, 1))!
        #expect(result == expected)
    }

    @Test("Custom every 3 months: period start calculation")
    func customMonthsPeriodStart() {
        let habitStart = makeDate(2026, 1, 1)
        let date = makeDate(2026, 5, 15) // 4.5 months in → second quarter
        let result = DateHelpers.periodStart(for: date, frequency: .custom, customValue: 3, customUnit: .months, habitStart: habitStart)
        let expected = makeDate(2026, 4, 1)
        #expect(result == expected)
    }

    @Test("Custom period end: every 5 days")
    func customDaysPeriodEnd() {
        let start = makeDate(2026, 4, 1)
        let result = DateHelpers.periodEnd(for: start, frequency: .custom, customValue: 5, customUnit: .days)
        let expected = makeDate(2026, 4, 6)
        #expect(result == expected)
    }

    @Test("Custom schedule returns next interval anchor")
    func customScheduleReturnsNextIntervalAnchor() {
        let habitStart = makeDate(2026, 4, 1)
        let date = makeDate(2026, 4, 2)
        let result = DateHelpers.nextScheduledDate(onOrAfter: date, frequency: .custom, customValue: 3, customUnit: .days, habitStart: habitStart)
        let expected = makeDate(2026, 4, 4)
        #expect(result == expected)
    }

    @Test("Custom schedule is due on interval anchor")
    func customScheduleDueOnIntervalAnchor() {
        let habitStart = makeDate(2026, 4, 1)
        let date = makeDate(2026, 4, 4)
        #expect(DateHelpers.isScheduled(on: date, frequency: .custom, customValue: 3, customUnit: .days, habitStart: habitStart))
    }

    @Test("Custom with nil values falls back to daily")
    func customNilFallback() {
        let date = makeDate(2026, 4, 15, hour: 10)
        let result = DateHelpers.periodStart(for: date, frequency: .custom)
        let expected = makeDate(2026, 4, 15)
        #expect(result == expected)
    }

    // MARK: - Edge cases

    @Test("Period start at midnight returns same day")
    func midnightPeriodStart() {
        let date = makeDate(2026, 4, 27)
        let result = DateHelpers.periodStart(for: date, frequency: .daily)
        #expect(result == date)
    }

    @Test("Period start at 23:59 returns same day")
    func endOfDayPeriodStart() {
        let date = makeDate(2026, 4, 27, hour: 23, minute: 59)
        let result = DateHelpers.periodStart(for: date, frequency: .daily)
        let expected = makeDate(2026, 4, 27)
        #expect(result == expected)
    }

    @Test("Custom period on exact habit start date")
    func customOnStartDate() {
        let habitStart = makeDate(2026, 4, 1)
        let result = DateHelpers.periodStart(for: habitStart, frequency: .custom, customValue: 7, customUnit: .days, habitStart: habitStart)
        #expect(result == habitStart)
    }

    @Test("Year boundary: Dec 31 to Jan 1")
    func yearBoundary() {
        let dec31 = makeDate(2026, 12, 31)
        let result = DateHelpers.periodStart(for: dec31, frequency: .yearly)
        let expected = makeDate(2026, 1, 1)
        #expect(result == expected)
    }

    @Test("Leap year Feb 29")
    func leapYear() {
        let date = makeDate(2028, 2, 29)
        let result = DateHelpers.periodStart(for: date, frequency: .monthly)
        let expected = makeDate(2028, 2, 1)
        #expect(result == expected)
    }

    // MARK: - Helpers

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

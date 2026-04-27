import Testing
import Foundation
@testable import Habits

@Suite("NotificationService")
struct NotificationServiceTests {
    @Test("Daily notifications skip today's 9 AM after that time has passed")
    func dailyNotificationsSkipPastTimeToday() {
        let from = makeDate(2026, 4, 27, hour: 10)
        let habit = Habit(name: "Meditate", frequency: .daily, startDate: makeDate(2026, 4, 1))

        let dates = NotificationService.notificationDates(for: habit, from: from, limit: 2)

        #expect(dates == [
            makeDate(2026, 4, 28, hour: 9),
            makeDate(2026, 4, 29, hour: 9)
        ])
    }

    @Test("Notifications use configured habit time")
    func notificationsUseConfiguredHabitTime() {
        let from = makeDate(2026, 4, 27, hour: 10)
        let habit = Habit(
            name: "Meditate",
            frequency: .daily,
            startDate: makeDate(2026, 4, 1),
            notificationHour: 15,
            notificationMinute: 30
        )

        let dates = NotificationService.notificationDates(for: habit, from: from, limit: 2)

        #expect(dates == [
            makeDate(2026, 4, 27, hour: 15, minute: 30),
            makeDate(2026, 4, 28, hour: 15, minute: 30)
        ])
    }

    @Test("Weekly notifications use the habit start weekday")
    func weeklyNotificationsUseStartWeekday() {
        let from = makeDate(2026, 4, 27, hour: 8)
        let habit = Habit(name: "Review", frequency: .weekly, startDate: makeDate(2026, 4, 29))

        let dates = NotificationService.notificationDates(for: habit, from: from, limit: 2)

        #expect(dates == [
            makeDate(2026, 4, 29, hour: 9),
            makeDate(2026, 5, 6, hour: 9)
        ])
    }

    @Test("Monthly notifications clamp to shorter months")
    func monthlyNotificationsClampShortMonths() {
        let from = makeDate(2026, 2, 1, hour: 8)
        let habit = Habit(name: "Budget", frequency: .monthly, startDate: makeDate(2026, 1, 31))

        let dates = NotificationService.notificationDates(for: habit, from: from, limit: 2)

        #expect(dates == [
            makeDate(2026, 2, 28, hour: 9),
            makeDate(2026, 3, 31, hour: 9)
        ])
    }

    @Test("Custom notifications use interval anchors")
    func customNotificationsUseIntervalAnchors() {
        let from = makeDate(2026, 4, 2, hour: 8)
        let habit = Habit(
            name: "Water plants",
            frequency: .custom,
            customIntervalValue: 3,
            customIntervalUnit: .days,
            startDate: makeDate(2026, 4, 1)
        )

        let dates = NotificationService.notificationDates(for: habit, from: from, limit: 2)

        #expect(dates == [
            makeDate(2026, 4, 4, hour: 9),
            makeDate(2026, 4, 7, hour: 9)
        ])
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

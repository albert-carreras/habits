import Testing
import Foundation
@testable import Habits

@Suite("Habit Model")
struct HabitModelTests {

    @Test("Default initializer sets expected values")
    func defaultInit() {
        let habit = Habit(name: "Meditate")
        #expect(habit.name == "Meditate")
        #expect(habit.frequency == .daily)
        #expect(habit.timesToComplete == 1)
        #expect(habit.notificationsEnabled == false)
        #expect(habit.notificationHour == nil)
        #expect(habit.notificationMinute == nil)
        #expect(habit.resolvedNotificationHour == 9)
        #expect(habit.resolvedNotificationMinute == 0)
        #expect(habit.customIntervalValue == nil)
        #expect(habit.customIntervalUnit == nil)
        #expect(habit.completions.isEmpty)
    }

    @Test("Custom frequency initializer")
    func customFrequencyInit() {
        let habit = Habit(
            name: "Review goals",
            frequency: .custom,
            customIntervalValue: 3,
            customIntervalUnit: .weeks,
            timesToComplete: 5,
            notificationsEnabled: true,
            notificationHour: 18,
            notificationMinute: 45
        )
        #expect(habit.name == "Review goals")
        #expect(habit.frequency == .custom)
        #expect(habit.customIntervalValue == 3)
        #expect(habit.customIntervalUnit == .weeks)
        #expect(habit.timesToComplete == 5)
        #expect(habit.notificationsEnabled == true)
        #expect(habit.notificationHour == 18)
        #expect(habit.notificationMinute == 45)
        #expect(habit.resolvedNotificationHour == 18)
        #expect(habit.resolvedNotificationMinute == 45)
    }

    @Test("Each habit gets a unique ID")
    func uniqueIDs() {
        let h1 = Habit(name: "A")
        let h2 = Habit(name: "B")
        #expect(h1.id != h2.id)
    }

    @Test("Start date defaults to now")
    func startDateDefault() {
        let before = Date.now
        let habit = Habit(name: "Test")
        let after = Date.now
        #expect(habit.startDate >= before)
        #expect(habit.startDate <= after)
    }

    @Test("CreatedAt is set on init")
    func createdAtSet() {
        let before = Date.now
        let habit = Habit(name: "Test")
        let after = Date.now
        #expect(habit.createdAt >= before)
        #expect(habit.createdAt <= after)
    }
}

@Suite("HabitCompletion Model")
struct HabitCompletionModelTests {

    @Test("Default initializer")
    func defaultInit() {
        let completion = HabitCompletion()
        #expect(completion.count == 1)
        #expect(completion.habit == nil)
    }

    @Test("Custom count initializer")
    func customCount() {
        let completion = HabitCompletion(count: 25)
        #expect(completion.count == 25)
    }

    @Test("Each completion gets a unique ID")
    func uniqueIDs() {
        let c1 = HabitCompletion()
        let c2 = HabitCompletion()
        #expect(c1.id != c2.id)
    }
}

@Suite("HabitFrequency Enum")
struct HabitFrequencyTests {

    @Test("All cases exist")
    func allCases() {
        let cases = HabitFrequency.allCases
        #expect(cases.count == 5)
        #expect(cases.contains(.daily))
        #expect(cases.contains(.weekly))
        #expect(cases.contains(.monthly))
        #expect(cases.contains(.yearly))
        #expect(cases.contains(.custom))
    }

    @Test("Raw values are display-friendly")
    func rawValues() {
        #expect(HabitFrequency.daily.rawValue == "Daily")
        #expect(HabitFrequency.weekly.rawValue == "Weekly")
        #expect(HabitFrequency.monthly.rawValue == "Monthly")
        #expect(HabitFrequency.yearly.rawValue == "Yearly")
        #expect(HabitFrequency.custom.rawValue == "Custom")
    }

    @Test("Identifiable IDs match raw values")
    func identifiable() {
        for freq in HabitFrequency.allCases {
            #expect(freq.id == freq.rawValue)
        }
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = HabitFrequency.weekly
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HabitFrequency.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("CustomIntervalUnit Enum")
struct CustomIntervalUnitTests {

    @Test("All cases exist")
    func allCases() {
        let cases = CustomIntervalUnit.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.days))
        #expect(cases.contains(.weeks))
        #expect(cases.contains(.months))
    }

    @Test("Raw values")
    func rawValues() {
        #expect(CustomIntervalUnit.days.rawValue == "Days")
        #expect(CustomIntervalUnit.weeks.rawValue == "Weeks")
        #expect(CustomIntervalUnit.months.rawValue == "Months")
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = CustomIntervalUnit.months
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomIntervalUnit.self, from: data)
        #expect(decoded == original)
    }
}

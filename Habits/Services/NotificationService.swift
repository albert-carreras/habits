import UserNotifications

struct NotificationService {
    static let maxScheduledNotificationsPerHabit = 16

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    @MainActor
    @discardableResult
    static func scheduleNotification(for habit: Habit, from date: Date = .now) async -> Bool {
        let center = UNUserNotificationCenter.current()
        removeNotification(for: habit)

        guard habit.notificationsEnabled else { return true }
        guard await requestPermission() else { return false }

        do {
            for request in makeNotificationRequests(for: habit, from: date) {
                try await center.add(request)
            }
            return true
        } catch {
            removeNotification(for: habit)
            return false
        }
    }

    static func removeNotification(for habit: Habit) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: habit))
    }

    static func notificationDates(
        for habit: Habit,
        from date: Date,
        limit: Int = maxScheduledNotificationsPerHabit,
        calendar: Calendar = .current
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: date)

        while dates.count < limit {
            let dueDate = DateHelpers.nextScheduledDate(
                onOrAfter: cursor,
                frequency: habit.frequency,
                customValue: habit.customIntervalValue,
                customUnit: habit.customIntervalUnit,
                habitStart: habit.startDate
            )
            var fireComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
            fireComponents.hour = 9
            fireComponents.minute = 0
            fireComponents.second = 0

            if let fireDate = calendar.date(from: fireComponents), fireDate > date {
                dates.append(fireDate)
            }

            guard let nextCursor = calendar.date(byAdding: .day, value: 1, to: dueDate) else { break }
            cursor = nextCursor
        }

        return dates
    }

    private static func makeNotificationRequests(for habit: Habit, from date: Date) -> [UNNotificationRequest] {
        notificationDates(for: habit, from: date).enumerated().map { index, fireDate in
            let content = UNMutableNotificationContent()
            content.title = "Habits"
            content.body = "Time to work on: \(habit.name)"
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            return UNNotificationRequest(
                identifier: "\(habit.id.uuidString)-\(index)",
                content: content,
                trigger: trigger
            )
        }
    }

    private static func notificationIdentifiers(for habit: Habit) -> [String] {
        [habit.id.uuidString] + (0..<64).map { "\(habit.id.uuidString)-\($0)" }
    }
}

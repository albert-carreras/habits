import Foundation

enum AppEnvironment {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    static var usesInMemoryStore: Bool {
        isUITesting || ProcessInfo.processInfo.environment["HABITS_IN_MEMORY_STORE"] == "1"
    }

    static var disablesWidgetSync: Bool {
        isUITesting || ProcessInfo.processInfo.environment["HABITS_DISABLE_WIDGET_SYNC"] == "1"
    }

    static var disablesRemoteSync: Bool {
        isUITesting || ProcessInfo.processInfo.environment["HABITS_DISABLE_REMOTE_SYNC"] == "1"
    }

    static var disablesHaptics: Bool {
        isUITesting || ProcessInfo.processInfo.environment["HABITS_DISABLE_HAPTICS"] == "1"
    }

    static var uiTestAccountEmail: String? {
        guard isUITesting else { return nil }
        let email = ProcessInfo.processInfo.environment["HABITS_UI_TEST_ACCOUNT_EMAIL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return email?.isEmpty == false ? email : nil
    }

    static var uiTestAccountUserID: UUID? {
        guard uiTestAccountEmail != nil else { return nil }
        return UUID(uuidString: "00000000-0000-0000-0000-000000000001")
    }

    static var uiTestAccountDeletionSucceeds: Bool {
        isUITesting && ProcessInfo.processInfo.environment["HABITS_UI_TEST_ACCOUNT_DELETION_SUCCEEDS"] == "1"
    }

    static var newItemDefaultDate: Date {
        guard isUITesting,
              let rawOffset = ProcessInfo.processInfo.environment["HABITS_UI_TEST_DEFAULT_DATE_OFFSET_DAYS"],
              let offset = Int(rawOffset),
              let date = Calendar.current.date(
                byAdding: .day,
                value: offset,
                to: Calendar.current.startOfDay(for: .now)
              ) else {
            return .now
        }

        return date
    }
}

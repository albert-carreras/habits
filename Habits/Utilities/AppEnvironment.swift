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
}

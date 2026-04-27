import SwiftUI
import SwiftData

@main
struct HabitsApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: AppEnvironment.usesInMemoryStore)
            modelContainer = try ModelContainer(for: Habit.self, HabitCompletion.self, configurations: configuration)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HabitListView()
        }
        .modelContainer(modelContainer)
    }
}

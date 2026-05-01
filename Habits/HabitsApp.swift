import SwiftUI
import SwiftData
import UserNotifications
import Supabase
import GoogleSignIn

@main
struct HabitsApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: AppEnvironment.usesInMemoryStore)
            modelContainer = try ModelContainer(for: Habit.self, HabitCompletion.self, Thing.self, configurations: configuration)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup("") {
            rootView
                .modifier(AppLaunchModifier())
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 720, height: 720)
        .commands {
            MacHabitCommands()
        }

        #else
        WindowGroup {
            rootView
                .modifier(AppLaunchModifier())
        }
        .modelContainer(modelContainer)
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        #if os(macOS)
        MacHabitListView()
            .frame(minWidth: 520, minHeight: 500)
        #else
        HabitListView()
        #endif
    }
}

private struct AppLaunchModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                AppHaptics.prepare()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
            .onOpenURL { url in
                if url.host == "add-thing" {
                    DeepLinkRouter.shared.pendingAction = .addThing
                    return
                }
                if GIDSignIn.sharedInstance.handle(url) { return }
                supabase.auth.handle(url)
            }
    }
}

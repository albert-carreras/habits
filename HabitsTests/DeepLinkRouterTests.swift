import Testing
import Foundation
@testable import Habits

@Suite("DeepLinkRouter")
struct DeepLinkRouterTests {
    @MainActor
    @Test("Add-thing URL is parsed correctly")
    func addThingURL() {
        let url = URL(string: "com.albertc.habit://add-thing")!
        #expect(url.host == "add-thing")
    }

    @MainActor
    @Test("Pending action can be set and cleared")
    func pendingActionLifecycle() {
        let router = DeepLinkRouter.shared
        router.pendingAction = .addThing

        #expect(router.pendingAction != nil)

        router.pendingAction = nil
        #expect(router.pendingAction == nil)
    }
}

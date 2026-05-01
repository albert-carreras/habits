import Testing
@testable import Habits

@Suite("App Haptics")
struct AppHapticsTests {
    @Test("Events map to restrained native feedback")
    func eventFeedbackMapping() {
        #expect(AppHapticEvent.selectionChanged.feedback == .selection)
        #expect(AppHapticEvent.lightTap.feedback == .impact(.soft))
        #expect(AppHapticEvent.habitProgressed(isComplete: false).feedback == .impact(.light))
        #expect(AppHapticEvent.habitProgressed(isComplete: true).feedback == .notification(.success))
        #expect(AppHapticEvent.completionCleared.feedback == .impact(.soft))
        #expect(AppHapticEvent.thingToggled(isComplete: false).feedback == .impact(.light))
        #expect(AppHapticEvent.thingToggled(isComplete: true).feedback == .notification(.success))
        #expect(AppHapticEvent.itemSaved.feedback == .notification(.success))
        #expect(AppHapticEvent.deleteRequested.feedback == .impact(.medium))
        #expect(AppHapticEvent.deleteConfirmed.feedback == .notification(.warning))
        #expect(AppHapticEvent.dateMoved.feedback == .selection)
        #expect(AppHapticEvent.warning.feedback == .notification(.warning))
    }
}

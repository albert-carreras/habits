import Testing
@testable import Habits

@Suite("Habit Row View")
struct HabitRowViewTests {

    @MainActor
    @Test("Completion indicator uses the large row control size")
    func completionIndicatorSize() {
        #expect(HabitRowView.completionIndicatorSize == 34)
        #expect(HabitRowView.ringDiameter == 30)
        #expect(HabitRowView.ringLineWidth == 3)
    }
}

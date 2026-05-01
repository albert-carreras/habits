#if os(macOS)
import Testing
@testable import Habits

@Suite("Mac Habit Commands")
@MainActor
struct MacHabitCommandModelTests {
    @Test("Haptics API is no-op compatible on macOS")
    func hapticsNoOpCompatibility() {
        AppHaptics.prepare()
        AppHaptics.perform(.selectionChanged)
        AppHaptics.perform(.habitProgressed(isComplete: true))
    }

    @Test("Selected mode controls add title")
    func selectedModeState() {
        let model = MacHabitCommandModel()

        #expect(model.addTitle == "New Habit")

        model.selectedMode = .things

        #expect(model.addTitle == "New Thing")
    }

    @Test("Mac rows use the shared completion control metrics")
    func rowControlMetrics() {
        #expect(MacHabitListView.rowIndicatorFrame == HabitRowView.completionIndicatorSize)
        #expect(MacHabitListView.rowRingDiameter == HabitRowView.ringDiameter)
        #expect(MacHabitListView.rowRingLineWidth == HabitRowView.ringLineWidth)
    }

    @Test("Mac content uses a single column grid")
    func contentColumnMetrics() {
        #expect(MacHabitListView.contentMaxWidth == 680)
        #expect(MacHabitListView.contentHorizontalPadding == 34)
        #expect(MacHabitListView.rowSpacing == 10)
        #expect(MacHabitListView.sectionSpacing == 22)
    }

    @Test("Settings rows own their card edge hit area")
    func settingsRowHitAreaMetrics() {
        #expect(SettingsView.settingsRowHorizontalPadding == 16)
        #expect(SettingsView.settingsRowVerticalPadding == 14)
        #expect(SettingsView.settingsDetailVerticalPadding == 12)
        #expect(SettingsView.settingsDividerLeadingPadding == 50)
    }

    @Test("Mac hides the content header on empty lists")
    func emptyListsHideContentHeader() {
        #expect(!MacHabitListView.showsContentHeader(isCurrentModeEmpty: true))
        #expect(MacHabitListView.showsContentHeader(isCurrentModeEmpty: false))
    }

    @Test("Commands call handlers")
    func commandHandlersCallThrough() {
        let model = MacHabitCommandModel()
        var addCount = 0
        var habitsCount = 0
        var thingsCount = 0
        var settingsCount = 0

        model.onAdd = { addCount += 1 }
        model.onSelectHabits = { habitsCount += 1 }
        model.onSelectThings = { thingsCount += 1 }
        model.onShowSettings = { settingsCount += 1 }

        model.add()
        model.selectHabits()
        model.selectThings()
        model.showSettings()

        #expect(addCount == 1)
        #expect(habitsCount == 1)
        #expect(thingsCount == 1)
        #expect(settingsCount == 1)
    }
}
#endif

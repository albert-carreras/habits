import XCTest

final class HabitsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateCompleteAndDeleteHabit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["No Habits"].waitForExistence(timeout: 5))

        app.buttons["add-habit-button"].tap()

        let nameField = app.textFields["habit-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Drink water")

        app.buttons["save-habit-button"].tap()

        let habitRow = app.buttons["habit-row-Drink water"]
        XCTAssertTrue(habitRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 1 complete today"].exists)

        habitRow.tap()
        XCTAssertTrue(app.staticTexts["1 of 1 complete today"].waitForExistence(timeout: 5))

        habitRow.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts["Delete Habit"].buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["No Habits"].waitForExistence(timeout: 5))
    }
}

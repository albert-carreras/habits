import XCTest

final class HabitsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateCompleteAndDeleteHabit() throws {
        let app = launchApp()

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

    @MainActor
    func testCreateCompleteAndDeleteThing() throws {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["No Habits"].waitForExistence(timeout: 5))

        app.buttons["mode-switcher-things"].tap()
        XCTAssertTrue(app.staticTexts["No Things"].waitForExistence(timeout: 5))

        app.buttons["add-thing-button"].tap()

        let titleField = app.textFields["thing-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Buy milk\n")

        let thingRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'thing-row-'")).element
        XCTAssertTrue(thingRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 thing open today"].exists)

        thingRow.tap()
        XCTAssertTrue(app.staticTexts["No things open today"].waitForExistence(timeout: 5))
        XCTAssertTrue(thingRow.exists)

        thingRow.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts["Delete Thing"].buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["No Things"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMoveThingToTomorrow() throws {
        let app = launchApp()

        app.buttons["mode-switcher-things"].tap()
        XCTAssertTrue(app.staticTexts["No Things"].waitForExistence(timeout: 5))

        app.buttons["add-thing-button"].tap()

        let titleField = app.textFields["thing-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Plan errands")

        app.buttons["save-thing-button"].tap()

        let thingRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'thing-row-'")).element
        XCTAssertTrue(thingRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today"].exists)

        thingRow.swipeLeft()
        app.buttons["Tomorrow"].tap()

        XCTAssertTrue(app.staticTexts["Later"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
        XCTAssertTrue(app.staticTexts["No things open today"].exists)

        thingRow.swipeLeft()
        XCTAssertFalse(app.buttons["Tomorrow"].exists)
        app.buttons["Today"].tap()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Later"].exists)
        XCTAssertTrue(app.staticTexts["1 thing open today"].exists)
    }

    @MainActor
    func testOpenSettingsSheet() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not signed in"].exists)
        XCTAssertTrue(app.buttons["sign-in-apple-button"].exists)
        XCTAssertTrue(app.buttons["sign-in-google-button"].exists)
        XCTAssertTrue(app.buttons["completed-things-button"].exists)
        XCTAssertTrue(app.buttons["export-backup-button"].exists)
        XCTAssertTrue(app.buttons["import-backup-button"].exists)
        XCTAssertFalse(app.buttons["force-sync-button"].exists)
        XCTAssertFalse(app.buttons["delete-account-button"].exists)
    }

    @MainActor
    func testCompletedThingsSettingsListShowsCompletedThings() throws {
        let app = launchApp()

        app.buttons["mode-switcher-things"].tap()
        XCTAssertTrue(app.staticTexts["No Things"].waitForExistence(timeout: 5))

        app.buttons["add-thing-button"].tap()

        let titleField = app.textFields["thing-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("File receipt\n")

        let thingRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'thing-row-'")).element
        XCTAssertTrue(thingRow.waitForExistence(timeout: 5))
        thingRow.tap()
        XCTAssertTrue(app.staticTexts["No things open today"].waitForExistence(timeout: 5))

        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["completed-things-button"].waitForExistence(timeout: 5))
        app.buttons["completed-things-button"].tap()

        XCTAssertTrue(app.staticTexts["Completed Things"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.staticTexts["File receipt"].exists)
    }

    @MainActor
    func testSignedInSettingsShowsDeleteAccountConfirmationChoices() throws {
        let app = launchApp(fakeAccountEmail: "person@example.com")

        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()

        XCTAssertTrue(app.staticTexts["person@example.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last synced at"].exists)
        XCTAssertTrue(app.staticTexts["Never"].exists)
        XCTAssertTrue(app.buttons["force-sync-button"].exists)

        let deleteButton = app.buttons["delete-account-button"]
        XCTAssertTrue(deleteButton.exists)
        deleteButton.tap()

        XCTAssertTrue(app.buttons["Delete Account, Keep Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete Account and Remove Local Data"].exists)
    }

    @MainActor
    func testDeleteAccountAndRemoveLocalDataClearsRowsWithoutCrashing() throws {
        let app = launchApp(fakeAccountEmail: "person@example.com", fakeAccountDeletionSucceeds: true)

        XCTAssertTrue(app.staticTexts["No Habits"].waitForExistence(timeout: 5))

        app.buttons["add-habit-button"].tap()
        let nameField = app.textFields["habit-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Read")
        app.buttons["save-habit-button"].tap()
        XCTAssertTrue(app.buttons["habit-row-Read"].waitForExistence(timeout: 5))

        app.buttons["mode-switcher-things"].tap()
        XCTAssertTrue(app.staticTexts["No Things"].waitForExistence(timeout: 5))
        app.buttons["add-thing-button"].tap()
        let titleField = app.textFields["thing-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Buy milk\n")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'thing-row-'")).element.waitForExistence(timeout: 5))

        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.staticTexts["person@example.com"].waitForExistence(timeout: 5))
        app.buttons["delete-account-button"].tap()
        XCTAssertTrue(app.buttons["Delete Account and Remove Local Data"].waitForExistence(timeout: 5))
        app.buttons["Delete Account and Remove Local Data"].tap()

        XCTAssertTrue(app.alerts["Account Deleted"].waitForExistence(timeout: 5))
        app.alerts["Account Deleted"].buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Not signed in"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Things"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateLaterHabit() throws {
        let app = launchApp(defaultDateOffsetDays: 1)

        XCTAssertTrue(app.staticTexts["No Habits"].waitForExistence(timeout: 5))

        app.buttons["add-habit-button"].tap()

        let nameField = app.textFields["habit-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Plan workout")

        app.buttons["save-habit-button"].tap()

        XCTAssertTrue(app.staticTexts["No habits due today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Later"].exists)
        XCTAssertTrue(app.buttons["habit-row-Plan workout"].exists)
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
    }

    @MainActor
    func testCreateLaterThing() throws {
        let app = launchApp(defaultDateOffsetDays: 1)

        XCTAssertTrue(app.staticTexts["No Habits"].waitForExistence(timeout: 5))

        app.buttons["mode-switcher-things"].tap()
        XCTAssertTrue(app.staticTexts["No Things"].waitForExistence(timeout: 5))

        app.buttons["add-thing-button"].tap()

        let titleField = app.textFields["thing-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Pack bag")

        app.buttons["save-thing-button"].tap()

        XCTAssertTrue(app.staticTexts["No things open today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Later"].exists)
        XCTAssertTrue(app.staticTexts["Pack bag"].exists)
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
    }

    private func launchApp(
        defaultDateOffsetDays: Int? = nil,
        fakeAccountEmail: String? = nil,
        fakeAccountDeletionSucceeds: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]

        if let defaultDateOffsetDays {
            app.launchEnvironment["HABITS_UI_TEST_DEFAULT_DATE_OFFSET_DAYS"] = "\(defaultDateOffsetDays)"
        }
        if let fakeAccountEmail {
            app.launchEnvironment["HABITS_UI_TEST_ACCOUNT_EMAIL"] = fakeAccountEmail
        }
        if fakeAccountDeletionSucceeds {
            app.launchEnvironment["HABITS_UI_TEST_ACCOUNT_DELETION_SUCCEEDS"] = "1"
        }

        app.launch()
        return app
    }
}

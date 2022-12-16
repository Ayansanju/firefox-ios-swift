// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest

class JumpBackInTests: BaseTestCase {
    func closeKeyboard() {
        waitForExistence(app.buttons["urlBar-cancel"], timeout: TIMEOUT)
        navigator.performAction(Action.CloseURLBarOpen)
        navigator.nowAt(NewTabScreen)
    }

    override func setUp() {
        super.setUp()

        closeKeyboard()

        // Since I can't scroll on M1, closing the "Switch Your Default Browser"
        // box makes the "Jump Back In" section visible without scrolling in the
        // last part of the test.
        if app.staticTexts["Switch Your Default Browser"].exists {
            app.buttons["Close"].firstMatch.tap()
        }

        // "Jump Back In" is enabled by default. See Settings -> Homepage
    }

    func testJumpBackInSection() {
        // Open a tab and visit a page
        navigator.openURL("https://www.example.com")
        waitUntilPageLoad()

        // Open a new tab
        navigator.goto(TabTray)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        closeKeyboard()

        // "Jump Back In" section is displayed
        waitForExistence(app.staticTexts["Jump Back In"])

        // The contextual hint box is not displayed consistently, so
        // I don't test for its existence.
    }

    func testGroupedTabs() {
        // Enable "Tab Groups" from Settings -> Tabs
        navigator.goto(BrowserTabMenu)
        navigator.goto(SettingsScreen)
        navigator.goto(TabsSettings)
        navigator.performAction(Action.ToggleTabGroups)
        navigator.goto(SettingsScreen)
        app.navigationBars.buttons["Done"].tap()
        navigator.nowAt(NewTabScreen)

        // Create 3 groups in tab tray
        let groups = ["test1", "test2", "test3"]
        for group in groups {
            for _ in 1...2 {
                navigator.goto(TabTray)
                navigator.performAction(Action.OpenNewTabFromTabTray)
                navigator.openURL(group)
                waitUntilPageLoad()
            }
        }

        // Open a new tab
        navigator.goto(TabTray)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        closeKeyboard()

        // Tap on the "test3" from "Jump Back In" section
        waitForExistence(app.staticTexts["Jump Back In"])
        // No "Test3" group is shown, but "Test2" group is shown.
        app.cells["JumpBackInCell"].staticTexts["Test2"].tap()
        waitForExistence(app.staticTexts["Open Tabs"])
        waitForExistence(app.staticTexts["Test2"])
        waitForExistence(app.staticTexts["Test3"])
    }

    func testPrivateTab() {
        // Visit https://www.twitter.com
        navigator.openURL("https://www.twitter.com")
        waitUntilPageLoad()

        // Open a new tab and check the "Jump Back In" Section"
        navigator.goto(TabTray)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        closeKeyboard()

        // Twitter tab is visible in the "Jump Back In" section
        waitForExistence(app.staticTexts["Jump Back In"])
        waitForExistence(app.cells["JumpBackInCell"])
        waitForExistence(app.cells["JumpBackInCell"].staticTexts["Twitter"])

        // Open private browsing
        navigator.goto(TabTray)
        navigator.toggleOn(userState.isPrivate, withAction: Action.TogglePrivateMode)

        // Visit YouTube in private browsing
        navigator.performAction(Action.OpenNewTabFromTabTray)
        navigator.openURL("https://www.youtube.com")
        waitUntilPageLoad()

        // Open a new tab in normal browsing and check the "Jump Back In" section.
        navigator.toggleOff(userState.isPrivate, withAction: Action.ToggleRegularMode)
        navigator.goto(NewTabScreen)
        closeKeyboard()

        // Twitter should be in "Jump Back In".
        waitForExistence(app.staticTexts["Jump Back In"])
        waitForExistence(app.cells["JumpBackInCell"])
        waitForExistence(app.cells["JumpBackInCell"].staticTexts["Twitter"])
        waitForNoExistence(app.cells["JumpBackInCell"].staticTexts["YouTube"])

        // Visit "amazon.com" and check the "Jump Back In" section.
        navigator.openURL("https://www.amazon.com")
        waitUntilPageLoad()

        navigator.goto(TabTray)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        closeKeyboard()

        // Amazon and Tiwtter are visible in the "Jump Back In" section
        waitForExistence(app.staticTexts["Jump Back In"])
        waitForExistence(app.cells["JumpBackInCell"])
        waitForExistence(app.cells["JumpBackInCell"].staticTexts["Amazon"])
        waitForExistence(app.cells["JumpBackInCell"].staticTexts["Twitter"])
        waitForNoExistence(app.cells["JumpBackInCell"].staticTexts["YouTube"])

        // Tap on Twitter from "Jump Back In"
        app.cells["JumpBackInCell"].staticTexts["Twitter"].tap()

        // The view is switched to the twitter tab
        var url = app.textFields["url"].value as! String
        XCTAssertEqual(url, "twitter.com/")

        // Open a new tab in normal browsing
        navigator.goto(TabTray)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        closeKeyboard()

        // Check the "Jump Back In Section".
        waitForExistence(app.staticTexts["Jump Back In"])
        waitForExistence(app.cells["JumpBackInCell"])

        // Amazon is visible in "Jump Back In".
        waitForExistence(app.cells["JumpBackInCell"].staticTexts["Amazon"])

        // Close the amazon tab.
        navigator.goto(TabTray)
        waitForExistence(app.staticTexts["Open Tabs"])
        app.cells["Amazon.com. Spend less. Smile more."].buttons["tab close"].tap()

        // Revisit the "Jump Back In" section
        navigator.performAction(Action.OpenNewTabFromTabTray)
        closeKeyboard()

        // The "Jump Back In" section is still here with twitter listed
        waitForExistence(app.staticTexts["Jump Back In"])
        waitForExistence(app.cells["JumpBackInCell"])
        // FXIOS-5448 - Amazon should not be listed because we've closed the Amazon tab
        // waitForNoExistence(app.cells["JumpBackInCell"].staticTexts["Amazon"])
        waitForExistence(app.cells["JumpBackInCell"].staticTexts["Twitter"])
        waitForNoExistence(app.cells["JumpBackInCell"].staticTexts["YouTube"])
    }
}

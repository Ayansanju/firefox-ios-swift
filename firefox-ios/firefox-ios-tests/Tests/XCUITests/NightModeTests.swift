// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common

class NightModeTests: BaseTestCase {
    private func checkNightModeOn() {
        mozWaitForElementToExist(app.tables.otherElements[StandardImageIdentifiers.Large.nightMode])
    }

    private func checkNightModeOff() {
        mozWaitForElementToExist(app.tables.otherElements[StandardImageIdentifiers.Large.nightMode])
    }

    // https://testrail.stage.mozaws.net/index.php?/cases/view/2307056
    func testNightModeUI() {
        let url1 = "test-example.html"
        // Go to a webpage, and select night mode on and off, check it's applied or not
        navigator.openURL(path(forTestPage: url1))

        // turn on the night mode
        navigator.performAction(Action.ToggleNightMode)
        navigator.nowAt(BrowserTab)
        navigator.goto(BrowserTabMenu)
        // checking night mode on or off
        checkNightModeOn()

        // turn off the night mode
        navigator.performAction(Action.ToggleNightMode)

        // checking night mode on or off
        navigator.nowAt(BrowserTab)
        navigator.goto(BrowserTabMenu)
        checkNightModeOff()
    }
}

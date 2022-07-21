// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

@testable import Client

import XCTest

class HomepageViewControllerTests: XCTestCase {

    func testHomepageViewController_creationFromBVC_hasNoLeaks() {
        let profile = MockProfile()
        let tabManager = TabManager(profile: profile, imageStore: nil)
        let browserViewController = BrowserViewController(profile: profile, tabManager: tabManager)

        browserViewController.addSubviews()
        browserViewController.showHomepage(inline: true)

        let expectation = self.expectation(description: "Firefox home page has finished animation")

        browserViewController.hideHomepage {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertNotNil(browserViewController.homepageViewController, "Homepage isn't nil after hiding it")
    }

    func testFirefoxHomeViewController_simpleCreation_hasNoLeaks() {
        let profile = MockProfile()
        let tabManager = TabManager(profile: profile, imageStore: nil)
        let urlBar = URLBarView(profile: profile)

        FeatureFlagsManager.shared.initializeDeveloperFeatures(with: profile)

        let firefoxHomeViewController = HomepageViewController(profile: profile,
                                                               tabManager: tabManager,
                                                               urlBar: urlBar)

        trackForMemoryLeaks(firefoxHomeViewController)
    }
}

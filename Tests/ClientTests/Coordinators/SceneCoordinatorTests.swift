// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Shared
import Common
@testable import Client

final class SceneCoordinatorTests: XCTestCase {
    private var mockRouter: MockRouter!

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        FeatureFlagsManager.shared.initializeDeveloperFeatures(with: AppContainer.shared.resolve())
        self.mockRouter = MockRouter(navigationController: MockNavigationController())
    }

    override func tearDown() {
        super.tearDown()
        mockRouter = nil
        AppContainer.shared.reset()
    }

    func testInitialState() {
        let scene = UIApplication.shared.windows.first?.windowScene
        let subject = SceneCoordinator(scene: scene!)
        trackForMemoryLeaks(subject)

        XCTAssertNotNil(subject.window)
        XCTAssertTrue(subject.childCoordinators.isEmpty)
    }

    func testStart_rootViewIsSceneContainer() {
        let subject = createSubject()
        subject.start()

        XCTAssertNotNil(subject.window)
        XCTAssertNotNil(mockRouter.rootViewController as? SceneContainer)
        XCTAssertEqual(mockRouter.setRootViewControllerCalled, 1)
    }

    func testStart_startsLaunchScreen() {
        let subject = createSubject()
        subject.start()

        XCTAssertNotNil(mockRouter.pushedViewController as? LaunchScreenViewController)
        XCTAssertEqual(mockRouter.pushCalled, 1)
    }

    func testLaunchWithLaunchType_launchFromScene() {
        let subject = createSubject()
        subject.launchWith(launchType: .intro(manager: IntroScreenManager(prefs: MockProfile().prefs)))

        XCTAssertEqual(subject.childCoordinators.count, 1)
        XCTAssertNotNil(subject.childCoordinators[0] as? LaunchCoordinator)
    }

    func testLaunchWithLaunchType_launchFromBrowser() {
        let subject = createSubject()
        subject.launchWith(launchType: .defaultBrowser)

        XCTAssertEqual(subject.childCoordinators.count, 1)
        XCTAssertNotNil(subject.childCoordinators[0] as? BrowserCoordinator)
    }

    func testLaunchBrowser() {
        let subject = createSubject()
        subject.launchBrowser()

        XCTAssertEqual(subject.childCoordinators.count, 1)
        XCTAssertNotNil(subject.childCoordinators[0] as? BrowserCoordinator)
    }

    func testChildLaunchCoordinatorIsDone_startsBrowser() throws {
        let subject = createSubject()
        subject.launchWith(launchType: .intro(manager: IntroScreenManager(prefs: MockProfile().prefs)))

        let childLaunchCoordinator = try XCTUnwrap(subject.childCoordinators[0] as? LaunchCoordinator)
        subject.didFinishLaunch(from: childLaunchCoordinator)

        XCTAssertEqual(subject.childCoordinators.count, 1)
        XCTAssertNotNil(subject.childCoordinators[0] as? BrowserCoordinator)
    }

    func testDidRequestToOpenInNewTab_hasNoBrowserCoordinator_doesNotFindRoute() {
        let expectedURL = URL(string: "www.example.com")!
        let subject = createSubject()

        subject.didRequestToOpenInNewTab(url: expectedURL, isPrivate: false)

        XCTAssertEqual(subject.childCoordinators.count, 0)
    }

    func testDidRequestToOpenInNewTab_hasBrowserCoordinator_findsRoute() {
        let expectedURL = URL(string: "www.example.com")!
        let subject = createSubject()
        let browserCoordinator = MockCoordinator(router: mockRouter)
        subject.add(child: browserCoordinator)

        subject.didRequestToOpenInNewTab(url: expectedURL, isPrivate: false)

        XCTAssertEqual(subject.childCoordinators.count, 1)
        XCTAssertEqual(browserCoordinator.findRouteCalled, 1)
        XCTAssertEqual(browserCoordinator.savedFindRoute, .search(url: expectedURL, isPrivate: false))
    }

    // MARK: - Helpers
    private func createSubject(file: StaticString = #file,
                               line: UInt = #line) -> SceneCoordinator {
        let scene = UIApplication.shared.windows.first?.windowScene
        let subject = SceneCoordinator(scene: scene!)
        // Replace created router from scene with a mock router so we don't trigger real navigation in our tests
        subject.router = mockRouter
        trackForMemoryLeaks(subject, file: file, line: line)
        return subject
    }
}

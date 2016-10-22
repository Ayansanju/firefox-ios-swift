/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Photos
import UIKit
import WebKit
import Shared
import Storage
import SnapKit
import XCGLogger
import Alamofire
import Account
import ReadingList
import MobileCoreServices
import WebImage

private let log = Logger.browserLogger

private let KVOLoading = "loading"
private let KVOEstimatedProgress = "estimatedProgress"
private let KVOURL = "URL"
private let KVOCanGoBack = "canGoBack"
private let KVOCanGoForward = "canGoForward"
private let KVOContentSize = "contentSize"

private let ActionSheetTitleMaxLength = 120

private struct BrowserViewControllerUX {
    private static let BackgroundColor = UIConstants.AppBackgroundColor
    private static let ShowHeaderTapAreaHeight: CGFloat = 32
    private static let BookmarkStarAnimationDuration: Double = 0.5
    private static let BookmarkStarAnimationOffset: CGFloat = 80
}

class BrowserViewController: UIViewController {
    var homePanelController: HomePanelViewController?
    var webViewContainer: UIView!
    var menuViewController: MenuViewController?
    var urlBar: URLBarView!
    var readerModeBar: ReaderModeBarView?
    var readerModeCache: ReaderModeCache
    private var statusBarOverlay: UIView!
    private(set) var toolbar: TabToolbar?
    private var searchController: SearchViewController?
    private var screenshotHelper: ScreenshotHelper!
    private var homePanelIsInline = false
    private var searchLoader: SearchLoader!
    private let snackBars = UIView()
    private let webViewContainerToolbar = UIView()
    private var findInPageBar: FindInPageBar?
    private let findInPageContainer = UIView()

    lazy private var customSearchEngineButton: UIButton = {
        let searchButton = UIButton()
        searchButton.setImage(UIImage(named: "AddSearch")?.imageWithRenderingMode(.AlwaysTemplate), forState: .Normal)
        searchButton.addTarget(self, action: #selector(BrowserViewController.addCustomSearchEngineForFocusedElement), forControlEvents: .TouchUpInside)
        return searchButton
    }()

    private var customSearchBarButton: UIBarButtonItem?

    // popover rotation handling
    private var displayedPopoverController: UIViewController?
    private var updateDisplayedPopoverProperties: (() -> ())?

    private var openInHelper: OpenInHelper?

    // location label actions
    private var pasteGoAction: AccessibleAction!
    private var pasteAction: AccessibleAction!
    private var copyAddressAction: AccessibleAction!

    private weak var tabTrayController: TabTrayController!

    private let profile: Profile
    let tabManager: TabManager

    // These views wrap the urlbar and toolbar to provide background effects on them
    var header: BlurWrapper!
    var headerBackdrop: UIView!
    var footer: UIView!
    var footerBackdrop: UIView!
    private var footerBackground: BlurWrapper?
    private var topTouchArea: UIButton!
    let urlBarTopTabsContainer = UIView(frame: CGRect.zero)

    // Backdrop used for displaying greyed background for private tabs
    var webViewContainerBackdrop: UIView!

    private var scrollController = TabScrollingController()

    private var keyboardState: KeyboardState?

    let WhiteListedUrls = ["\\/\\/itunes\\.apple\\.com\\/"]

    // Tracking navigation items to record history types.
    // TODO: weak references?
    var ignoredNavigation = Set<WKNavigation>()
    var typedNavigation = [WKNavigation: VisitType]()
    var navigationToolbar: TabToolbarProtocol {
        return toolbar ?? urlBar
    }
    
    var topTabsViewController: TopTabsViewController?
    let topTabsContainer = UIView(frame: CGRect.zero)

    init(profile: Profile, tabManager: TabManager) {
        self.profile = profile
        self.tabManager = tabManager
        self.readerModeCache = DiskReaderModeCache.sharedInstance
        super.init(nibName: nil, bundle: nil)
        didInit()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        if UIDevice.currentDevice().userInterfaceIdiom == .Phone {
            return UIInterfaceOrientationMask.AllButUpsideDown
        } else {
            return UIInterfaceOrientationMask.All
        }
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)

        displayedPopoverController?.dismissViewControllerAnimated(true) {
            self.displayedPopoverController = nil
        }

        guard let displayedPopoverController = self.displayedPopoverController else {
            return
        }

        coordinator.animateAlongsideTransition(nil) { context in
            self.updateDisplayedPopoverProperties?()
            self.presentViewController(displayedPopoverController, animated: true, completion: nil)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        log.debug("BVC received memory warning")
    }

    private func didInit() {
        screenshotHelper = ScreenshotHelper(controller: self)
        tabManager.addDelegate(self)
        tabManager.addNavigationDelegate(self)
    }

    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return UIStatusBarStyle.LightContent
    }

    func shouldShowFooterForTraitCollection(previousTraitCollection: UITraitCollection) -> Bool {
        return previousTraitCollection.verticalSizeClass != .Compact &&
               previousTraitCollection.horizontalSizeClass != .Regular
    }

    func shouldShowTopTabsForTraitCollection(newTraitCollection: UITraitCollection) -> Bool {
        guard AppConstants.MOZ_TOP_TABS else {
            return false
        }
        return newTraitCollection.verticalSizeClass == .Regular &&
            newTraitCollection.horizontalSizeClass == .Regular
    }

    func toggleSnackBarVisibility(show show: Bool) {
        if show {
            UIView.animateWithDuration(0.1, animations: { self.snackBars.hidden = false })
        } else {
            snackBars.hidden = true
        }
    }

    private func updateToolbarStateForTraitCollection(newCollection: UITraitCollection, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator? = nil) {
        let showToolbar = shouldShowFooterForTraitCollection(newCollection)
        let showTopTabs = shouldShowTopTabsForTraitCollection(newCollection)

        if UI_USER_INTERFACE_IDIOM() == .Pad,
            let mvc = menuViewController where showToolbar != (toolbar != nil) {
            // Hide the menu, and then re-open it so that the menu is always the correct one for the given traits
            mvc.dismissViewControllerAnimated(true, completion: nil)
            coordinator?.animateAlongsideTransition(nil, completion: { _ in
                self.tabToolbarDidPressMenu(self.navigationToolbar, button: self.navigationToolbar.menuButton)
            })
        }

        urlBar.topTabsIsShowing = showTopTabs
        urlBar.setShowToolbar(!showToolbar)
        toolbar?.removeFromSuperview()
        toolbar?.tabToolbarDelegate = nil
        footerBackground?.removeFromSuperview()
        footerBackground = nil
        toolbar = nil

        if showToolbar {
            toolbar = TabToolbar()
            toolbar?.tabToolbarDelegate = self
            footerBackground = BlurWrapper(view: toolbar!)
            footerBackground?.translatesAutoresizingMaskIntoConstraints = false

            // Need to reset the proper blur style
            if let selectedTab = tabManager.selectedTab where selectedTab.isPrivate {
                footerBackground!.blurStyle = .Dark
                toolbar?.applyTheme(Theme.PrivateMode)
            }
            footer.addSubview(footerBackground!)
        }
        
        if showTopTabs {
            if topTabsViewController == nil {
                let topTabsViewController = TopTabsViewController(tabManager: tabManager)
                topTabsViewController.delegate = self
                addChildViewController(topTabsViewController)
                topTabsViewController.view.frame = topTabsContainer.frame
                topTabsContainer.addSubview(topTabsViewController.view)
                topTabsViewController.view.snp_makeConstraints { make in
                    make.edges.equalTo(topTabsContainer)
                    make.height.equalTo(TopTabsUX.TopTabsViewHeight)
                }
                self.topTabsViewController = topTabsViewController
                tabManager.addNavigationDelegate(topTabsViewController)
            }
            topTabsContainer.snp_updateConstraints { make in
                make.height.equalTo(TopTabsUX.TopTabsViewHeight)
            }
            header.disableBlur = true
        } else {
            topTabsContainer.snp_updateConstraints { make in
                make.height.equalTo(0)
            }
            topTabsViewController?.view.removeFromSuperview()
            topTabsViewController?.removeFromParentViewController()
            topTabsViewController = nil
            header.disableBlur = false
        }

        view.setNeedsUpdateConstraints()
        if let home = homePanelController {
            home.view.setNeedsUpdateConstraints()
        }

        if let tab = tabManager.selectedTab,
               webView = tab.webView {
            updateURLBarDisplayURL(tab)
            navigationToolbar.updateBackStatus(webView.canGoBack)
            navigationToolbar.updateForwardStatus(webView.canGoForward)
            navigationToolbar.updateReloadStatus(tab.loading ?? false)
        }
    }

    override func willTransitionToTraitCollection(newCollection: UITraitCollection, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransitionToTraitCollection(newCollection, withTransitionCoordinator: coordinator)

        // During split screen launching on iPad, this callback gets fired before viewDidLoad gets a chance to
        // set things up. Make sure to only update the toolbar state if the view is ready for it.
        if isViewLoaded() {
            updateToolbarStateForTraitCollection(newCollection, withTransitionCoordinator: coordinator)
        }

        displayedPopoverController?.dismissViewControllerAnimated(true, completion: nil)

        // WKWebView looks like it has a bug where it doesn't invalidate it's visible area when the user
        // performs a device rotation. Since scrolling calls
        // _updateVisibleContentRects (https://github.com/WebKit/webkit/blob/master/Source/WebKit2/UIProcess/API/Cocoa/WKWebView.mm#L1430)
        // this method nudges the web view's scroll view by a single pixel to force it to invalidate.
        if let scrollView = self.tabManager.selectedTab?.webView?.scrollView {
            let contentOffset = scrollView.contentOffset
            coordinator.animateAlongsideTransition({ context in
                scrollView.setContentOffset(CGPoint(x: contentOffset.x, y: contentOffset.y + 1), animated: true)
                self.scrollController.showToolbars(animated: false)
            }, completion: { context in
                scrollView.setContentOffset(CGPoint(x: contentOffset.x, y: contentOffset.y), animated: false)
            })
        }
    }

    func SELappDidEnterBackgroundNotification() {
        displayedPopoverController?.dismissViewControllerAnimated(false) {
            self.displayedPopoverController = nil
        }
    }

    func SELtappedTopArea() {
        scrollController.showToolbars(animated: true)
    }

    func SELappWillResignActiveNotification() {
        // Dismiss any popovers that might be visible
        displayedPopoverController?.dismissViewControllerAnimated(false) {
            self.displayedPopoverController = nil
        }

        // If we are displying a private tab, hide any elements in the tab that we wouldn't want shown
        // when the app is in the home switcher
        guard let privateTab = tabManager.selectedTab where privateTab.isPrivate else {
            return
        }

        webViewContainerBackdrop.alpha = 1
        webViewContainer.alpha = 0
        urlBar.locationContainer.alpha = 0
        topTabsViewController?.switchForegroundStatus(isInForeground: false)
        presentedViewController?.popoverPresentationController?.containerView?.alpha = 0
        presentedViewController?.view.alpha = 0
    }

    func SELappDidBecomeActiveNotification() {
        // Re-show any components that might have been hidden because they were being displayed
        // as part of a private mode tab
        UIView.animateWithDuration(0.2, delay: 0, options: UIViewAnimationOptions.CurveEaseInOut, animations: {
            self.webViewContainer.alpha = 1
            self.urlBar.locationContainer.alpha = 1
            self.topTabsViewController?.switchForegroundStatus(isInForeground: true)
            self.presentedViewController?.popoverPresentationController?.containerView?.alpha = 1
            self.presentedViewController?.view.alpha = 1
            self.view.backgroundColor = UIColor.clearColor()
        }, completion: { _ in
            self.webViewContainerBackdrop.alpha = 0
        })

        // Re-show toolbar which might have been hidden during scrolling (prior to app moving into the background)
        scrollController.showToolbars(animated: false)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: BookmarkStatusChangedNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillResignActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidEnterBackgroundNotification, object: nil)
    }

    override func viewDidLoad() {
        log.debug("BVC viewDidLoad…")
        super.viewDidLoad()
        log.debug("BVC super viewDidLoad called.")
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BrowserViewController.SELBookmarkStatusDidChange(_:)), name: BookmarkStatusChangedNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BrowserViewController.SELappWillResignActiveNotification), name: UIApplicationWillResignActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BrowserViewController.SELappDidBecomeActiveNotification), name: UIApplicationDidBecomeActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BrowserViewController.SELappDidEnterBackgroundNotification), name: UIApplicationDidEnterBackgroundNotification, object: nil)
        KeyboardHelper.defaultHelper.addDelegate(self)

        log.debug("BVC adding footer and header…")
        footerBackdrop = UIView()
        footerBackdrop.backgroundColor = UIColor.whiteColor()
        view.addSubview(footerBackdrop)
        headerBackdrop = UIView()
        headerBackdrop.backgroundColor = UIColor.whiteColor()
        view.addSubview(headerBackdrop)

        log.debug("BVC setting up webViewContainer…")
        webViewContainerBackdrop = UIView()
        webViewContainerBackdrop.backgroundColor = UIColor.grayColor()
        webViewContainerBackdrop.alpha = 0
        view.addSubview(webViewContainerBackdrop)

        webViewContainer = UIView()
        webViewContainer.addSubview(webViewContainerToolbar)
        view.addSubview(webViewContainer)

        log.debug("BVC setting up status bar…")
        // Temporary work around for covering the non-clipped web view content
        statusBarOverlay = UIView()
        statusBarOverlay.backgroundColor = BrowserViewControllerUX.BackgroundColor
        view.addSubview(statusBarOverlay)

        log.debug("BVC setting up top touch area…")
        topTouchArea = UIButton()
        topTouchArea.isAccessibilityElement = false
        topTouchArea.addTarget(self, action: #selector(BrowserViewController.SELtappedTopArea), forControlEvents: UIControlEvents.TouchUpInside)
        view.addSubview(topTouchArea)

        log.debug("BVC setting up URL bar…")
        // Setup the URL bar, wrapped in a view to get transparency effect
        urlBar = URLBarView()
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        urlBar.delegate = self
        urlBar.tabToolbarDelegate = self
        header = BlurWrapper(view: urlBarTopTabsContainer)
        urlBarTopTabsContainer.addSubview(urlBar)
        urlBarTopTabsContainer.addSubview(topTabsContainer)
        view.addSubview(header)

        // UIAccessibilityCustomAction subclass holding an AccessibleAction instance does not work, thus unable to generate AccessibleActions and UIAccessibilityCustomActions "on-demand" and need to make them "persistent" e.g. by being stored in BVC
        pasteGoAction = AccessibleAction(name: NSLocalizedString("Paste & Go", comment: "Paste the URL into the location bar and visit"), handler: { () -> Bool in
            if let pasteboardContents = UIPasteboard.generalPasteboard().string {
                self.urlBar(self.urlBar, didSubmitText: pasteboardContents)
                return true
            }
            return false
        })
        pasteAction = AccessibleAction(name: NSLocalizedString("Paste", comment: "Paste the URL into the location bar"), handler: { () -> Bool in
            if let pasteboardContents = UIPasteboard.generalPasteboard().string {
                // Enter overlay mode and fire the text entered callback to make the search controller appear.
                self.urlBar.enterOverlayMode(pasteboardContents, pasted: true)
                self.urlBar(self.urlBar, didEnterText: pasteboardContents)
                return true
            }
            return false
        })
        copyAddressAction = AccessibleAction(name: NSLocalizedString("Copy Address", comment: "Copy the URL from the location bar"), handler: { () -> Bool in
            if let url = self.urlBar.currentURL {
                UIPasteboard.generalPasteboard().URL = url
            }
            return true
        })


        log.debug("BVC setting up search loader…")
        searchLoader = SearchLoader(profile: profile, urlBar: urlBar)

        footer = UIView()
        self.view.addSubview(footer)
        self.view.addSubview(snackBars)
        snackBars.backgroundColor = UIColor.clearColor()
        self.view.addSubview(findInPageContainer)

        scrollController.urlBar = urlBar
        scrollController.header = header
        scrollController.footer = footer
        scrollController.snackBars = snackBars

        log.debug("BVC updating toolbar state…")
        self.updateToolbarStateForTraitCollection(self.traitCollection)

        log.debug("BVC setting up constraints…")
        setupConstraints()
        log.debug("BVC done.")
    }

    private func setupConstraints() {
        topTabsContainer.snp_makeConstraints { make in
            make.leading.trailing.equalTo(self.header)
            make.top.equalTo(urlBarTopTabsContainer)
        }
        
        urlBar.snp_makeConstraints { make in
            make.leading.trailing.bottom.equalTo(urlBarTopTabsContainer)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.top.equalTo(topTabsContainer.snp_bottom)
        }

        header.snp_makeConstraints { make in
            scrollController.headerTopConstraint = make.top.equalTo(snp_topLayoutGuideBottom).constraint
            make.left.right.equalTo(self.view)
        }

        headerBackdrop.snp_makeConstraints { make in
            make.edges.equalTo(self.header)
        }

        webViewContainerBackdrop.snp_makeConstraints { make in
            make.edges.equalTo(webViewContainer)
        }

        webViewContainerToolbar.snp_makeConstraints { make in
            make.left.right.top.equalTo(webViewContainer)
            make.height.equalTo(0)
        }
    }

    override func viewDidLayoutSubviews() {
        log.debug("BVC viewDidLayoutSubviews…")
        super.viewDidLayoutSubviews()
        statusBarOverlay.snp_remakeConstraints { make in
            make.top.left.right.equalTo(self.view)
            make.height.equalTo(self.topLayoutGuide.length)
        }
        self.appDidUpdateState(getCurrentAppState())
        log.debug("BVC done.")
    }

    func loadQueuedTabs() {
        log.debug("Loading queued tabs in the background.")

        // Chain off of a trivial deferred in order to run on the background queue.
        succeed().upon() { res in
            self.dequeueQueuedTabs()
        }
    }

    private func dequeueQueuedTabs() {
        assert(!NSThread.currentThread().isMainThread, "This must be called in the background.")
        self.profile.queue.getQueuedTabs() >>== { cursor in

            // This assumes that the DB returns rows in some kind of sane order.
            // It does in practice, so WFM.
            log.debug("Queue. Count: \(cursor.count).")
            if cursor.count <= 0 {
                return
            }

            let urls = cursor.flatMap { $0?.url.asURL }
            if !urls.isEmpty {
                dispatch_async(dispatch_get_main_queue()) {
                    self.tabManager.addTabsForURLs(urls, zombie: false)
                }
            }

            // Clear *after* making an attempt to open. We're making a bet that
            // it's better to run the risk of perhaps opening twice on a crash,
            // rather than losing data.
            self.profile.queue.clearQueuedTabs()
        }
    }

    override func viewWillAppear(animated: Bool) {
        log.debug("BVC viewWillAppear.")
        super.viewWillAppear(animated)
        log.debug("BVC super.viewWillAppear done.")

        // On iPhone, if we are about to show the On-Boarding, blank out the tab so that it does
        // not flash before we present. This change of alpha also participates in the animation when
        // the intro view is dismissed.
        if UIDevice.currentDevice().userInterfaceIdiom == .Phone {
            self.view.alpha = (profile.prefs.intForKey(IntroViewControllerSeenProfileKey) != nil) ? 1.0 : 0.0
        }

        if PLCrashReporter.sharedReporter().hasPendingCrashReport() {
            PLCrashReporter.sharedReporter().purgePendingCrashReport()
            showRestoreTabsAlert()
        } else {
            log.debug("Restoring tabs.")
            tabManager.restoreTabs()
            log.debug("Done restoring tabs.")
        }

        log.debug("Updating tab count.")
        updateTabCountUsingTabManager(tabManager, animated: false)
        log.debug("BVC done.")

        NSNotificationCenter.defaultCenter().addObserver(self,
                                                         selector: #selector(BrowserViewController.openSettings),
                                                         name: NotificationStatusNotificationTapped,
                                                         object: nil)
    }

    private func showRestoreTabsAlert() {
        guard shouldRestoreTabs() else {
            self.tabManager.addTabAndSelect()
            return
        }

        let alert = UIAlertController.restoreTabsAlert(
            okayCallback: { _ in
                self.tabManager.restoreTabs()
                self.updateTabCountUsingTabManager(self.tabManager, animated: false)
            },
            noCallback: { _ in
                self.tabManager.addTabAndSelect()
                self.updateTabCountUsingTabManager(self.tabManager, animated: false)
            }
        )

        self.presentViewController(alert, animated: true, completion: nil)
    }

    private func shouldRestoreTabs() -> Bool {
        guard let tabsToRestore = TabManager.tabsToRestore() else { return false }
        let onlyNoHistoryTabs = !tabsToRestore.every { $0.sessionData?.urls.count > 1 || !AboutUtils.isAboutHomeURL($0.sessionData?.urls.first) }
        return !onlyNoHistoryTabs && !DebugSettingsBundleOptions.skipSessionRestore
    }

    override func viewDidAppear(animated: Bool) {
        log.debug("BVC viewDidAppear.")
        presentIntroViewController()
        log.debug("BVC intro presented.")
        self.webViewContainerToolbar.hidden = false

        screenshotHelper.viewIsVisible = true
        log.debug("BVC taking pending screenshots….")
        screenshotHelper.takePendingScreenshots(tabManager.tabs)
        log.debug("BVC done taking screenshots.")

        log.debug("BVC calling super.viewDidAppear.")
        super.viewDidAppear(animated)
        log.debug("BVC done.")

        if shouldShowWhatsNewTab() {
            if let whatsNewURL = SupportUtils.URLForTopic("new-ios") {
                self.openURLInNewTab(whatsNewURL, isPrivileged: false)
                profile.prefs.setString(AppInfo.appVersion, forKey: LatestAppVersionProfileKey)
            }
        }

        showQueuedAlertIfAvailable()
    }

    private func shouldShowWhatsNewTab() -> Bool {
        guard let latestMajorAppVersion = profile.prefs.stringForKey(LatestAppVersionProfileKey)?.componentsSeparatedByString(".").first else {
            return DeviceInfo.hasConnectivity()
        }

        return latestMajorAppVersion != AppInfo.majorAppVersion && DeviceInfo.hasConnectivity()
    }

    private func showQueuedAlertIfAvailable() {
        if let queuedAlertInfo = tabManager.selectedTab?.dequeueJavascriptAlertPrompt() {
            let alertController = queuedAlertInfo.alertController()
            alertController.delegate = self
            presentViewController(alertController, animated: true, completion: nil)
        }
    }

    override func viewWillDisappear(animated: Bool) {
        screenshotHelper.viewIsVisible = false
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationStatusNotificationTapped, object: nil)
    }

    func resetBrowserChrome() {
        // animate and reset transform for tab chrome
        urlBar.updateAlphaForSubviews(1)

        [header,
            footer,
            readerModeBar,
            footerBackdrop,
            headerBackdrop].forEach { view in
                view?.transform = CGAffineTransformIdentity
        }
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()

        topTouchArea.snp_remakeConstraints { make in
            make.top.left.right.equalTo(self.view)
            make.height.equalTo(BrowserViewControllerUX.ShowHeaderTapAreaHeight)
        }

        readerModeBar?.snp_remakeConstraints { make in
            make.top.equalTo(self.header.snp_bottom).constraint
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.leading.trailing.equalTo(self.view)
        }

        webViewContainer.snp_remakeConstraints { make in
            make.left.right.equalTo(self.view)

            if let readerModeBarBottom = readerModeBar?.snp_bottom {
                make.top.equalTo(readerModeBarBottom)
            } else {
                make.top.equalTo(self.header.snp_bottom)
            }

            let findInPageHeight = (findInPageBar == nil) ? 0 : UIConstants.ToolbarHeight
            if let toolbar = self.toolbar {
                make.bottom.equalTo(toolbar.snp_top).offset(-findInPageHeight)
            } else {
                make.bottom.equalTo(self.view).offset(-findInPageHeight)
            }
        }

        // Setup the bottom toolbar
        toolbar?.snp_remakeConstraints { make in
            make.edges.equalTo(self.footerBackground!)
            make.height.equalTo(UIConstants.ToolbarHeight)
        }

        footer.snp_remakeConstraints { make in
            scrollController.footerBottomConstraint = make.bottom.equalTo(self.view.snp_bottom).constraint
            make.top.equalTo(self.snackBars.snp_top)
            make.leading.trailing.equalTo(self.view)
        }

        footerBackdrop.snp_remakeConstraints { make in
            make.edges.equalTo(self.footer)
        }

        updateSnackBarConstraints()
        footerBackground?.snp_remakeConstraints { make in
            make.bottom.left.right.equalTo(self.footer)
            make.height.equalTo(UIConstants.ToolbarHeight)
        }
        urlBar.setNeedsUpdateConstraints()

        // Remake constraints even if we're already showing the home controller.
        // The home controller may change sizes if we tap the URL bar while on about:home.
        homePanelController?.view.snp_remakeConstraints { make in
            make.top.equalTo(self.urlBar.snp_bottom)
            make.left.right.equalTo(self.view)
            if self.homePanelIsInline {
                make.bottom.equalTo(self.toolbar?.snp_top ?? self.view.snp_bottom)
            } else {
                make.bottom.equalTo(self.view.snp_bottom)
            }
        }

        findInPageContainer.snp_remakeConstraints { make in
            make.left.right.equalTo(self.view)

            if let keyboardHeight = keyboardState?.intersectionHeightForView(self.view) where keyboardHeight > 0 {
                make.bottom.equalTo(self.view).offset(-keyboardHeight)
            } else if let toolbar = self.toolbar {
                make.bottom.equalTo(toolbar.snp_top)
            } else {
                make.bottom.equalTo(self.view)
            }
        }
    }

    private func showHomePanelController(inline inline: Bool) {
        log.debug("BVC showHomePanelController.")
        homePanelIsInline = inline

        if homePanelController == nil {
            let homePanelController = HomePanelViewController()
            homePanelController.profile = profile
            homePanelController.delegate = self
            homePanelController.appStateDelegate = self
            homePanelController.url = tabManager.selectedTab?.displayURL
            homePanelController.view.alpha = 0
            self.homePanelController = homePanelController

            addChildViewController(homePanelController)
            view.addSubview(homePanelController.view)
            homePanelController.didMoveToParentViewController(self)
        }
        guard let homePanelController = self.homePanelController else {
            assertionFailure("homePanelController is still nil after assignment.")
            return
        }

        let panelNumber = tabManager.selectedTab?.url?.fragment

        // splitting this out to see if we can get better crash reports when this has a problem
        var newSelectedButtonIndex = 0
        if let numberArray = panelNumber?.componentsSeparatedByString("=") {
            if let last = numberArray.last, lastInt = Int(last) {
                newSelectedButtonIndex = lastInt
            }
        }
        homePanelController.selectedPanel = HomePanelType(rawValue: newSelectedButtonIndex)
        homePanelController.isPrivateMode = tabManager.selectedTab?.isPrivate ?? false

        // We have to run this animation, even if the view is already showing because there may be a hide animation running
        // and we want to be sure to override its results.
        UIView.animateWithDuration(0.2, animations: { () -> Void in
            homePanelController.view.alpha = 1
        }, completion: { finished in
            if finished {
                self.webViewContainer.accessibilityElementsHidden = true
                UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
            }
        })
        view.setNeedsUpdateConstraints()
        log.debug("BVC done with showHomePanelController.")
    }

    private func hideHomePanelController() {
        if let controller = homePanelController {
            self.homePanelController = nil
            UIView.animateWithDuration(0.2, delay: 0, options: .BeginFromCurrentState, animations: { () -> Void in
                controller.view.alpha = 0
            }, completion: { _ in
                controller.willMoveToParentViewController(nil)
                controller.view.removeFromSuperview()
                controller.removeFromParentViewController()
                self.webViewContainer.accessibilityElementsHidden = false
                UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)

                // Refresh the reading view toolbar since the article record may have changed
                if let readerMode = self.tabManager.selectedTab?.getHelper(name: ReaderMode.name()) as? ReaderMode where readerMode.state == .Active {
                    self.showReaderModeBar(animated: false)
                }
            })
        }
    }

    private func updateInContentHomePanel(url: NSURL?) {
        if !urlBar.inOverlayMode {
            if AboutUtils.isAboutHomeURL(url) {
                showHomePanelController(inline: true)
            } else {
                hideHomePanelController()
            }
        }
    }

    private func showSearchController() {
        if searchController != nil {
            return
        }

        let isPrivate = tabManager.selectedTab?.isPrivate ?? false
        searchController = SearchViewController(isPrivate: isPrivate)
        searchController!.searchEngines = profile.searchEngines
        searchController!.searchDelegate = self
        searchController!.profile = self.profile

        searchLoader.addListener(searchController!)

        addChildViewController(searchController!)
        view.addSubview(searchController!.view)
        searchController!.view.snp_makeConstraints { make in
            make.top.equalTo(self.urlBar.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
            return
        }

        homePanelController?.view?.hidden = true

        searchController!.didMoveToParentViewController(self)
    }

    private func hideSearchController() {
        if let searchController = searchController {
            searchController.willMoveToParentViewController(nil)
            searchController.view.removeFromSuperview()
            searchController.removeFromParentViewController()
            self.searchController = nil
            homePanelController?.view?.hidden = false
        }
    }

    private func finishEditingAndSubmit(url: NSURL, visitType: VisitType) {
        urlBar.currentURL = url
        urlBar.leaveOverlayMode()

        guard let tab = tabManager.selectedTab else {
            return
        }

        if let webView = tab.webView {
            resetSpoofedUserAgentIfRequired(webView, newURL: url)
        }

        if let nav = tab.loadRequest(PrivilegedRequest(URL: url)) {
            self.recordNavigationInTab(tab, navigation: nav, visitType: visitType)
        }
    }

    func addBookmark(tabState: TabState) {
        guard let url = tabState.url, absoluteString = url.absoluteString else { return }
        let shareItem = ShareItem(url: absoluteString, title: tabState.title, favicon: tabState.favicon)
        profile.bookmarks.shareItem(shareItem)
        var userData = [QuickActions.TabURLKey: shareItem.url]
        if let title = shareItem.title {
            userData[QuickActions.TabTitleKey] = title
        }
        QuickActions.sharedInstance.addDynamicApplicationShortcutItemOfType(.OpenLastBookmark,
            withUserData: userData,
            toApplication: UIApplication.sharedApplication())
        if let tab = tabManager.getTabForURL(url) {
            tab.isBookmarked = true
        }
    }

    private func animateBookmarkStar() {
        let offset: CGFloat
        let button: UIButton!

        if let toolbar: TabToolbar = self.toolbar {
            offset = BrowserViewControllerUX.BookmarkStarAnimationOffset * -1
            button = toolbar.bookmarkButton
        } else {
            offset = BrowserViewControllerUX.BookmarkStarAnimationOffset
            button = self.urlBar.bookmarkButton
        }

        JumpAndSpinAnimator.animateFromView(button.imageView ?? button, offset: offset, completion: nil)
    }

    private func removeBookmark(tabState: TabState) {
        guard let url = tabState.url, absoluteString = url.absoluteString else { return }
        profile.bookmarks.modelFactory >>== {
            $0.removeByURL(absoluteString)
                .uponQueue(dispatch_get_main_queue()) { res in
                if res.isSuccess {
                    if let tab = self.tabManager.getTabForURL(url) {
                        tab.isBookmarked = false
                    }
                }
            }
        }
    }

    func SELBookmarkStatusDidChange(notification: NSNotification) {
        if let bookmark = notification.object as? BookmarkItem {
            if bookmark.url == urlBar.currentURL?.absoluteString {
                if let userInfo = notification.userInfo as? Dictionary<String, Bool> {
                    if let added = userInfo["added"] {
                        if let tab = self.tabManager.getTabForURL(urlBar.currentURL!) {
                            tab.isBookmarked = false
                        }
                    }
                }
            }
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        if urlBar.inOverlayMode {
            urlBar.SELdidClickCancel()
            return true
        } else if let selectedTab = tabManager.selectedTab where selectedTab.canGoBack {
            selectedTab.goBack()
            return true
        }
        return false
    }

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String: AnyObject]?, context: UnsafeMutablePointer<Void>) {
        let webView = object as! WKWebView
        guard let path = keyPath else { assertionFailure("Unhandled KVO key: \(keyPath)"); return }
        switch path {
        case KVOEstimatedProgress:
            guard webView == tabManager.selectedTab?.webView,
                let progress = change?[NSKeyValueChangeNewKey] as? Float else { break }
            
            urlBar.updateProgressBar(progress)
        case KVOLoading:
            guard let loading = change?[NSKeyValueChangeNewKey] as? Bool else { break }

            if webView == tabManager.selectedTab?.webView {
                navigationToolbar.updateReloadStatus(loading)
            }

            if (!loading) {
                runScriptsOnWebView(webView)
            }
        case KVOURL:
            guard let tab = tabManager[webView] else { break }

            // To prevent spoofing, only change the URL immediately if the new URL is on
            // the same origin as the current URL. Otherwise, do nothing and wait for
            // didCommitNavigation to confirm the page load.
            if tab.url?.origin == webView.URL?.origin {
                tab.url = webView.URL

                if tab === tabManager.selectedTab && !tab.restoring {
                    updateUIForReaderHomeStateForTab(tab)
                }
            }
        case KVOCanGoBack:
            guard webView == tabManager.selectedTab?.webView,
                let canGoBack = change?[NSKeyValueChangeNewKey] as? Bool else { break }
            
            navigationToolbar.updateBackStatus(canGoBack)
        case KVOCanGoForward:
            guard webView == tabManager.selectedTab?.webView,
                let canGoForward = change?[NSKeyValueChangeNewKey] as? Bool else { break }

            navigationToolbar.updateForwardStatus(canGoForward)
        default:
            assertionFailure("Unhandled KVO key: \(keyPath)")
        }
    }

    private func runScriptsOnWebView(webView: WKWebView) {
        webView.evaluateJavaScript("__firefox__.favicons.getFavicons()", completionHandler: nil)

        if AppConstants.MOZ_CONTENT_METADATA_PARSING {
            webView.evaluateJavaScript("__firefox__.metadata.extractMetadata()", completionHandler: nil)
        }
    }

    private func updateUIForReaderHomeStateForTab(tab: Tab) {
        updateURLBarDisplayURL(tab)
        scrollController.showToolbars(animated: false)

        if let url = tab.url {
            if ReaderModeUtils.isReaderModeURL(url) {
                showReaderModeBar(animated: false)
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(BrowserViewController.SELDynamicFontChanged(_:)), name: NotificationDynamicFontChanged, object: nil)
            } else {
                hideReaderModeBar(animated: false)
                NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationDynamicFontChanged, object: nil)
            }

            updateInContentHomePanel(url)
        }
    }

    private func isWhitelistedUrl(url: NSURL) -> Bool {
        for entry in WhiteListedUrls {
            if let _ = url.absoluteString?.rangeOfString(entry, options: .RegularExpressionSearch) {
                return UIApplication.sharedApplication().canOpenURL(url)
            }
        }
        return false
    }

    /// Updates the URL bar text and button states.
    /// Call this whenever the page URL changes.
    private func updateURLBarDisplayURL(tab: Tab) {
        urlBar.currentURL = tab.displayURL

        let isPage = tab.displayURL?.isWebPage() ?? false
        navigationToolbar.updatePageStatus(isWebPage: isPage)

        guard let url = tab.displayURL?.absoluteString else {
            return
        }

        profile.bookmarks.modelFactory >>== {
            $0.isBookmarked(url).uponQueue(dispatch_get_main_queue()) { [weak tab] result in
                guard let bookmarked = result.successValue else {
                    log.error("Error getting bookmark status: \(result.failureValue).")
                    return
                }
                tab?.isBookmarked = bookmarked
            }
        }
    }
    // Mark: Opening New Tabs

    func switchToPrivacyMode(isPrivate isPrivate: Bool ) {
        applyTheme(isPrivate ? Theme.PrivateMode : Theme.NormalMode)

        let tabTrayController = self.tabTrayController ?? TabTrayController(tabManager: tabManager, profile: profile, tabTrayDelegate: self)
        if tabTrayController.privateMode != isPrivate {
            tabTrayController.changePrivacyMode(isPrivate)
        }
        self.tabTrayController = tabTrayController
    }

    func switchToTabForURLOrOpen(url: NSURL, isPrivate: Bool = false, isPrivileged: Bool) {
        popToBVC()
        if let tab = tabManager.getTabForURL(url) {
            tabManager.selectTab(tab)
        } else {
            openURLInNewTab(url, isPrivate: isPrivate, isPrivileged: isPrivileged)
        }
    }

    func openURLInNewTab(url: NSURL?, isPrivate: Bool = false, isPrivileged: Bool) {
        if let selectedTab = tabManager.selectedTab {
            screenshotHelper.takeScreenshot(selectedTab)
        }
        let request: NSURLRequest?
        if let url = url {
            request = isPrivileged ? PrivilegedRequest(URL: url) : NSURLRequest(URL: url)
        } else {
            request = nil
        }

        switchToPrivacyMode(isPrivate: isPrivate)
        tabManager.addTabAndSelect(request, isPrivate: isPrivate)
    }

    func openBlankNewTabAndFocus(isPrivate isPrivate: Bool = false) {
        popToBVC()
        openURLInNewTab(nil, isPrivate: isPrivate, isPrivileged: true)
        urlBar.tabLocationViewDidTapLocation(urlBar.locationView)
    }

    private func popToBVC() {
        guard let currentViewController = navigationController?.topViewController else {
                return
        }
        currentViewController.dismissViewControllerAnimated(true, completion: nil)
        if currentViewController != self {
            self.navigationController?.popViewControllerAnimated(true)
        } else if urlBar.inOverlayMode {
            urlBar.SELdidClickCancel()
        }
    }

    // Mark: User Agent Spoofing

    private func resetSpoofedUserAgentIfRequired(webView: WKWebView, newURL: NSURL) {
        // Reset the UA when a different domain is being loaded
        if webView.URL?.host != newURL.host {
            webView.customUserAgent = nil
        }
    }

    private func restoreSpoofedUserAgentIfRequired(webView: WKWebView, newRequest: NSURLRequest) {
        // Restore any non-default UA from the request's header
        let ua = newRequest.valueForHTTPHeaderField("User-Agent")
        webView.customUserAgent = ua != UserAgent.defaultUserAgent() ? ua : nil
    }

    private func presentActivityViewController(url: NSURL, tab: Tab? = nil, sourceView: UIView?, sourceRect: CGRect, arrowDirection: UIPopoverArrowDirection) {
        var activities = [UIActivity]()

        let findInPageActivity = FindInPageActivity() { [unowned self] in
            self.updateFindInPageVisibility(visible: true)
        }
        activities.append(findInPageActivity)

        if let tab = tab where (tab.getHelper(name: ReaderMode.name()) as? ReaderMode)?.state != .Active {
            let requestDesktopSiteActivity = RequestDesktopSiteActivity(requestMobileSite: tab.desktopSite) { [unowned tab] in
                tab.toggleDesktopSite()
            }
            activities.append(requestDesktopSiteActivity)
        }

        let helper = ShareExtensionHelper(url: url, tab: tab, activities: activities)

        let controller = helper.createActivityViewController({ [unowned self] completed, _ in
            // After dismissing, check to see if there were any prompts we queued up
            self.showQueuedAlertIfAvailable()

            // Usually the popover delegate would handle nil'ing out the references we have to it
            // on the BVC when displaying as a popover but the delegate method doesn't seem to be
            // invoked on iOS 10. See Bug 1297768 for additional details.
            self.displayedPopoverController = nil
            self.updateDisplayedPopoverProperties = nil

            if completed {
                // We don't know what share action the user has chosen so we simply always
                // update the toolbar and reader mode bar to reflect the latest status.
                if let tab = tab {
                    self.updateURLBarDisplayURL(tab)
                }
                self.updateReaderModeBar()
            }
        })

        let setupPopover = { [unowned self] in
            if let popoverPresentationController = controller.popoverPresentationController {
                popoverPresentationController.sourceView = sourceView
                popoverPresentationController.sourceRect = sourceRect
                popoverPresentationController.permittedArrowDirections = arrowDirection
                popoverPresentationController.delegate = self
            }
        }

        setupPopover()

        if controller.popoverPresentationController != nil {
            displayedPopoverController = controller
            updateDisplayedPopoverProperties = setupPopover
        }

        self.presentViewController(controller, animated: true, completion: nil)
    }

    private func updateFindInPageVisibility(visible visible: Bool) {
        if visible {
            if findInPageBar == nil {
                let findInPageBar = FindInPageBar()
                self.findInPageBar = findInPageBar
                findInPageBar.delegate = self
                findInPageContainer.addSubview(findInPageBar)

                findInPageBar.snp_makeConstraints { make in
                    make.edges.equalTo(findInPageContainer)
                    make.height.equalTo(UIConstants.ToolbarHeight)
                }

                updateViewConstraints()

                // We make the find-in-page bar the first responder below, causing the keyboard delegates
                // to fire. This, in turn, will animate the Find in Page container since we use the same
                // delegate to slide the bar up and down with the keyboard. We don't want to animate the
                // constraints added above, however, so force a layout now to prevent these constraints
                // from being lumped in with the keyboard animation.
                findInPageBar.layoutIfNeeded()
            }

            self.findInPageBar?.becomeFirstResponder()
        } else if let findInPageBar = self.findInPageBar {
            findInPageBar.endEditing(true)
            guard let webView = tabManager.selectedTab?.webView else { return }
            webView.evaluateJavaScript("__firefox__.findDone()", completionHandler: nil)
            findInPageBar.removeFromSuperview()
            self.findInPageBar = nil
            updateViewConstraints()
        }
    }

    override func canBecomeFirstResponder() -> Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        // Make the web view the first responder so that it can show the selection menu.
        return tabManager.selectedTab?.webView?.becomeFirstResponder() ?? false
    }

    func reloadTab() {
        if(homePanelController == nil) {
            tabManager.selectedTab?.reload()
        }
    }

    func goBack() {
        if(tabManager.selectedTab?.canGoBack == true && homePanelController == nil) {
            tabManager.selectedTab?.goBack()
        }
    }
    func goForward() {
        if(tabManager.selectedTab?.canGoForward == true && homePanelController == nil) {
            tabManager.selectedTab?.goForward()
        }
    }

    func findOnPage() {
        if(homePanelController == nil) {
            tab( (tabManager.selectedTab)!, didSelectFindInPageForSelection: "")
        }
    }

    func selectLocationBar() {
        scrollController.showToolbars(animated: true)
        urlBar.tabLocationViewDidTapLocation(urlBar.locationView)
    }

    func newTab() {
        openBlankNewTabAndFocus(isPrivate: false)
    }
    func newPrivateTab() {
        openBlankNewTabAndFocus(isPrivate: true)
    }

    func closeTab() {
        if(tabManager.tabs.count > 1) {
            tabManager.removeTab(tabManager.selectedTab!)
        } else {
            //need to close the last tab and show the favorites screen thing
        }
    }

    func nextTab() {
        if(tabManager.selectedIndex < (tabManager.tabs.count - 1) ) {
            tabManager.selectTab(tabManager.tabs[tabManager.selectedIndex+1])
        } else {
            if(tabManager.tabs.count > 1) {
                tabManager.selectTab(tabManager.tabs[0])
            }
        }
    }

    func previousTab() {
        if(tabManager.selectedIndex > 0) {
            tabManager.selectTab(tabManager.tabs[tabManager.selectedIndex-1])
        } else {
            if(tabManager.tabs.count > 1) {
                tabManager.selectTab(tabManager.tabs[tabManager.count-1])
            }
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "r", modifierFlags: .Command, action: #selector(BrowserViewController.reloadTab), discoverabilityTitle: Strings.ReloadPageTitle),
            UIKeyCommand(input: "[", modifierFlags: .Command, action: #selector(BrowserViewController.goBack), discoverabilityTitle: Strings.BackTitle),
            UIKeyCommand(input: UIKeyInputLeftArrow, modifierFlags: .Command, action: #selector(BrowserViewController.goBack), discoverabilityTitle: Strings.BackTitle),
            UIKeyCommand(input: "]", modifierFlags: .Command, action: #selector(BrowserViewController.goForward), discoverabilityTitle: Strings.ForwardTitle),
            UIKeyCommand(input: UIKeyInputRightArrow, modifierFlags: .Command, action: #selector(BrowserViewController.goForward), discoverabilityTitle: Strings.ForwardTitle),

            UIKeyCommand(input: "f", modifierFlags: .Command, action: #selector(BrowserViewController.findOnPage), discoverabilityTitle: Strings.FindTitle),
            UIKeyCommand(input: "l", modifierFlags: .Command, action: #selector(BrowserViewController.selectLocationBar), discoverabilityTitle: Strings.SelectLocationBarTitle),
            UIKeyCommand(input: "t", modifierFlags: .Command, action: #selector(BrowserViewController.newTab), discoverabilityTitle: Strings.NewTabTitle),
            UIKeyCommand(input: "p", modifierFlags: [.Command, .Shift], action: #selector(BrowserViewController.newPrivateTab), discoverabilityTitle: Strings.NewPrivateTabTitle),
            UIKeyCommand(input: "w", modifierFlags: .Command, action: #selector(BrowserViewController.closeTab), discoverabilityTitle: Strings.CloseTabTitle),
            UIKeyCommand(input: "\t", modifierFlags: .Control, action: #selector(BrowserViewController.nextTab), discoverabilityTitle: Strings.ShowNextTabTitle),
            UIKeyCommand(input: UIKeyInputRightArrow, modifierFlags: [.Command, .Shift], action: #selector(BrowserViewController.nextTab), discoverabilityTitle: Strings.ShowNextTabTitle),
            UIKeyCommand(input: "\t", modifierFlags: [.Control, .Shift], action: #selector(BrowserViewController.previousTab), discoverabilityTitle: Strings.ShowPreviousTabTitle),
            UIKeyCommand(input: UIKeyInputLeftArrow, modifierFlags: [.Command, .Shift], action: #selector(BrowserViewController.previousTab), discoverabilityTitle: Strings.ShowPreviousTabTitle),
        ]
    }

    private func getCurrentAppState() -> AppState {
        return mainStore.updateState(getCurrentUIState())
    }

    private func getCurrentUIState() -> UIState {
        if let homePanelController = homePanelController {
            return .HomePanels(homePanelState: homePanelController.homePanelState)
        }
        guard let tab = tabManager.selectedTab else {
            return .Loading
        }
        return .Tab(tabState: tab.tabState)
    }

    @objc private func openSettings() {
        assert(NSThread.isMainThread(), "Opening settings requires being invoked on the main thread")

        let settingsTableViewController = AppSettingsTableViewController()
        settingsTableViewController.profile = profile
        settingsTableViewController.tabManager = tabManager
        settingsTableViewController.settingsDelegate = self

        let controller = SettingsNavigationController(rootViewController: settingsTableViewController)
        controller.popoverDelegate = self
        controller.modalPresentationStyle = UIModalPresentationStyle.FormSheet
        self.presentViewController(controller, animated: true, completion: nil)
    }
}

extension BrowserViewController: AppStateDelegate {

    func appDidUpdateState(appState: AppState) {
        menuViewController?.appState = appState
        toolbar?.appDidUpdateState(appState)
        urlBar?.appDidUpdateState(appState)
    }
}

extension BrowserViewController: MenuActionDelegate {
    func performMenuAction(action: MenuAction, withAppState appState: AppState) {
        if let menuAction = AppMenuAction(rawValue: action.action) {
            switch menuAction {
            case .OpenNewNormalTab:
                self.openURLInNewTab(nil, isPrivate: false, isPrivileged: true)
            // this is a case that is only available in iOS9
            case .OpenNewPrivateTab:
                self.openURLInNewTab(nil, isPrivate: true, isPrivileged: true)
            case .FindInPage:
                self.updateFindInPageVisibility(visible: true)
            case .ToggleBrowsingMode:
                guard let tab = tabManager.selectedTab else { break }
                tab.toggleDesktopSite()
            case .ToggleBookmarkStatus:
                switch appState.ui {
                case .Tab(let tabState):
                    self.toggleBookmarkForTabState(tabState)
                default: break
                }
            case .ShowImageMode:
                self.setNoImageMode(false)
            case .HideImageMode:
                self.setNoImageMode(true)
            case .ShowNightMode:
                NightModeHelper.setNightMode(self.profile.prefs, tabManager: self.tabManager, enabled: false)
            case .HideNightMode:
                NightModeHelper.setNightMode(self.profile.prefs, tabManager: self.tabManager, enabled: true)
            case .OpenSettings:
                self.openSettings()
            case .OpenTopSites:
                openHomePanel(.TopSites, forAppState: appState)
            case .OpenBookmarks:
                openHomePanel(.Bookmarks, forAppState: appState)
            case .OpenHistory:
                openHomePanel(.History, forAppState: appState)
            case .OpenReadingList:
                openHomePanel(.ReadingList, forAppState: appState)
            case .SetHomePage:
                guard let tab = tabManager.selectedTab else { break }
                HomePageHelper(prefs: profile.prefs).setHomePage(toTab: tab, withNavigationController: navigationController)
            case .OpenHomePage:
                guard let tab = tabManager.selectedTab else { break }
                HomePageHelper(prefs: profile.prefs).openHomePage(inTab: tab, withNavigationController: navigationController)
            case .SharePage:
                guard let url = tabManager.selectedTab?.url else { break }
                let sourceView = self.navigationToolbar.menuButton
                let tab = tabManager.selectedTab
                presentActivityViewController(url, tab: tab, sourceView: sourceView.superview, sourceRect: sourceView.frame, arrowDirection: .Up)
            default: break
            }
        }
    }

    private func openHomePanel(panel: HomePanelType, forAppState appState: AppState) {
        switch appState.ui {
        case .Tab(_):
            self.openURLInNewTab(panel.localhostURL, isPrivate: appState.ui.isPrivate(), isPrivileged: true)
        case .HomePanels(_):
            self.homePanelController?.selectedPanel = panel
        default: break
        }
    }
}


extension BrowserViewController: SettingsDelegate {
    func settingsOpenURLInNewTab(url: NSURL) {
        self.openURLInNewTab(url, isPrivileged: false)
    }
}


extension BrowserViewController: PresentingModalViewControllerDelegate {
    func dismissPresentedModalViewController(modalViewController: UIViewController, animated: Bool) {
        self.appDidUpdateState(getCurrentAppState())
        self.dismissViewControllerAnimated(animated, completion: nil)
    }
}

/**
 * History visit management.
 * TODO: this should be expanded to track various visit types; see Bug 1166084.
 */
extension BrowserViewController {
    func ignoreNavigationInTab(tab: Tab, navigation: WKNavigation) {
        self.ignoredNavigation.insert(navigation)
    }

    func recordNavigationInTab(tab: Tab, navigation: WKNavigation, visitType: VisitType) {
        self.typedNavigation[navigation] = visitType
    }

    /**
     * Untrack and do the right thing.
     */
    func getVisitTypeForTab(tab: Tab, navigation: WKNavigation?) -> VisitType? {
        guard let navigation = navigation else {
            // See https://github.com/WebKit/webkit/blob/master/Source/WebKit2/UIProcess/Cocoa/NavigationState.mm#L390
            return VisitType.Link
        }

        if let _ = self.ignoredNavigation.remove(navigation) {
            return nil
        }

        return self.typedNavigation.removeValueForKey(navigation) ?? VisitType.Link
    }
}

extension BrowserViewController: URLBarDelegate {

    func urlBarDidPressReload(urlBar: URLBarView) {
        tabManager.selectedTab?.reload()
    }

    func urlBarDidPressStop(urlBar: URLBarView) {
        tabManager.selectedTab?.stop()
    }

    func urlBarDidPressTabs(urlBar: URLBarView) {
        self.webViewContainerToolbar.hidden = true
        updateFindInPageVisibility(visible: false)

        let tabTrayController = TabTrayController(tabManager: tabManager, profile: profile, tabTrayDelegate: self)

        if let tab = tabManager.selectedTab {
            screenshotHelper.takeScreenshot(tab)
        }

        self.navigationController?.pushViewController(tabTrayController, animated: false)
        self.tabTrayController = tabTrayController
    }

    func urlBarDidPressReaderMode(urlBar: URLBarView) {
        if let tab = tabManager.selectedTab {
            if let readerMode = tab.getHelper(name: "ReaderMode") as? ReaderMode {
                switch readerMode.state {
                case .Available:
                    enableReaderMode()
                case .Active:
                    disableReaderMode()
                case .Unavailable:
                    break
                }
            }
        }
    }

    func urlBarDidLongPressReaderMode(urlBar: URLBarView) -> Bool {
        guard let tab = tabManager.selectedTab,
               url = tab.displayURL,
               absoluteString = url.absoluteString,
               result = profile.readingList?.createRecordWithURL(absoluteString, title: tab.title ?? "", addedBy: UIDevice.currentDevice().name)
            else {
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Could not add page to Reading list", comment: "Accessibility message e.g. spoken by VoiceOver after adding current webpage to the Reading List failed."))
                return false
        }

        switch result {
        case .Success:
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Added page to Reading List", comment: "Accessibility message e.g. spoken by VoiceOver after the current page gets added to the Reading List using the Reader View button, e.g. by long-pressing it or by its accessibility custom action."))
            // TODO: https://bugzilla.mozilla.org/show_bug.cgi?id=1158503 provide some form of 'this has been added' visual feedback?
        case .Failure(let error):
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Could not add page to Reading List. Maybe it's already there?", comment: "Accessibility message e.g. spoken by VoiceOver after the user wanted to add current page to the Reading List and this was not done, likely because it already was in the Reading List, but perhaps also because of real failures."))
            log.error("readingList.createRecordWithURL(url: \"\(url.absoluteString)\", ...) failed with error: \(error)")
        }
        return true
    }

    func locationActionsForURLBar(urlBar: URLBarView) -> [AccessibleAction] {
        if UIPasteboard.generalPasteboard().string != nil {
            return [pasteGoAction, pasteAction, copyAddressAction]
        } else {
            return [copyAddressAction]
        }
    }

    func urlBarDisplayTextForURL(url: NSURL?) -> String? {
        // use the initial value for the URL so we can do proper pattern matching with search URLs
        var searchURL = self.tabManager.selectedTab?.currentInitialURL
        if searchURL == nil || ErrorPageHelper.isErrorPageURL(searchURL!) {
            searchURL = url
        }
        return profile.searchEngines.queryForSearchURL(searchURL) ?? url?.absoluteString
    }

    func urlBarDidLongPressLocation(urlBar: URLBarView) {
        let longPressAlertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)

        for action in locationActionsForURLBar(urlBar) {
            longPressAlertController.addAction(action.alertAction(style: .Default))
        }

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Label for Cancel button"), style: .Cancel, handler: { (alert: UIAlertAction) -> Void in
        })
        longPressAlertController.addAction(cancelAction)

        let setupPopover = { [unowned self] in
            if let popoverPresentationController = longPressAlertController.popoverPresentationController {
                popoverPresentationController.sourceView = urlBar
                popoverPresentationController.sourceRect = urlBar.frame
                popoverPresentationController.permittedArrowDirections = .Any
                popoverPresentationController.delegate = self
            }
        }

        setupPopover()

        if longPressAlertController.popoverPresentationController != nil {
            displayedPopoverController = longPressAlertController
            updateDisplayedPopoverProperties = setupPopover
        }

        self.presentViewController(longPressAlertController, animated: true, completion: nil)
    }

    func urlBarDidPressScrollToTop(urlBar: URLBarView) {
        if let selectedTab = tabManager.selectedTab {
            // Only scroll to top if we are not showing the home view controller
            if homePanelController == nil {
                selectedTab.webView?.scrollView.setContentOffset(CGPointZero, animated: true)
            }
        }
    }

    func urlBarLocationAccessibilityActions(urlBar: URLBarView) -> [UIAccessibilityCustomAction]? {
        return locationActionsForURLBar(urlBar).map { $0.accessibilityCustomAction }
    }

    func urlBar(urlBar: URLBarView, didEnterText text: String) {
        searchLoader.query = text

        if text.isEmpty {
            hideSearchController()
        } else {
            showSearchController()
            searchController!.searchQuery = text
        }
    }

    func urlBar(urlBar: URLBarView, didSubmitText text: String) {
        // If we can't make a valid URL, do a search query.
        // If we still don't have a valid URL, something is broken. Give up.
        let engine = profile.searchEngines.defaultEngine
        guard let url = URIFixup.getURL(text) ??
                        engine.searchURLForQuery(text) else {
            log.error("Error handling URL entry: \"\(text)\".")
            return
        }

        Telemetry.recordEvent(SearchTelemetry.makeEvent(engine: engine, source: .URLBar))

        finishEditingAndSubmit(url, visitType: VisitType.Typed)
    }

    func urlBarDidEnterOverlayMode(urlBar: URLBarView) {
        if .BlankPage == NewTabAccessors.getNewTabPage(profile.prefs) {
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
        } else {
            showHomePanelController(inline: false)
        }
    }

    func urlBarDidLeaveOverlayMode(urlBar: URLBarView) {
        hideSearchController()
        updateInContentHomePanel(tabManager.selectedTab?.url)
    }
}

extension BrowserViewController: TabToolbarDelegate {
    func tabToolbarDidPressBack(tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goBack()
    }

    func tabToolbarDidLongPressBack(tabToolbar: TabToolbarProtocol, button: UIButton) {
        showBackForwardList()
    }

    func tabToolbarDidPressReload(tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.reload()
    }

    func tabToolbarDidLongPressReload(tabToolbar: TabToolbarProtocol, button: UIButton) {

        guard let tab = tabManager.selectedTab where tab.webView?.URL != nil && (tab.getHelper(name: ReaderMode.name()) as? ReaderMode)?.state != .Active else {
            return
        }

        let toggleActionTitle: String
        if tab.desktopSite {
            toggleActionTitle = NSLocalizedString("Request Mobile Site", comment: "Action Sheet Button for Requesting the Mobile Site")
        } else {
            toggleActionTitle = NSLocalizedString("Request Desktop Site", comment: "Action Sheet Button for Requesting the Desktop Site")
        }

        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        controller.addAction(UIAlertAction(title: toggleActionTitle, style: .Default, handler: { _ in tab.toggleDesktopSite() }))
        controller.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment:"Label for Cancel button"), style: .Cancel, handler: nil))
        controller.popoverPresentationController?.sourceView = toolbar ?? urlBar
        controller.popoverPresentationController?.sourceRect = button.frame
        presentViewController(controller, animated: true, completion: nil)
    }

    func tabToolbarDidPressStop(tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.stop()
    }

    func tabToolbarDidPressForward(tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goForward()
    }

    func tabToolbarDidLongPressForward(tabToolbar: TabToolbarProtocol, button: UIButton) {
        showBackForwardList()
    }

    func tabToolbarDidPressMenu(tabToolbar: TabToolbarProtocol, button: UIButton) {
        // ensure that any keyboards or spinners are dismissed before presenting the menu
        UIApplication.sharedApplication().sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, forEvent:nil)
        // check the trait collection
        // open as modal if portrait\
        let presentationStyle: MenuViewPresentationStyle = (self.traitCollection.horizontalSizeClass == .Compact && traitCollection.verticalSizeClass == .Regular) ? .Modal : .Popover
        let mvc = MenuViewController(withAppState: getCurrentAppState(), presentationStyle: presentationStyle)
        mvc.delegate = self
        mvc.actionDelegate = self
        mvc.menuTransitionDelegate = MenuPresentationAnimator()
        mvc.modalPresentationStyle = presentationStyle == .Modal ? .OverCurrentContext : .Popover

        if let popoverPresentationController = mvc.popoverPresentationController {
            popoverPresentationController.backgroundColor = UIColor.clearColor()
            popoverPresentationController.delegate = self
            popoverPresentationController.sourceView = button
            popoverPresentationController.sourceRect = CGRect(x: button.frame.width/2, y: button.frame.size.height * 0.75, width: 1, height: 1)
            popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirection.Up
        }

        self.presentViewController(mvc, animated: true, completion: nil)
        menuViewController = mvc
    }

    private func setNoImageMode(enabled: Bool) {
        self.profile.prefs.setBool(enabled, forKey: PrefsKeys.KeyNoImageModeStatus)
        for tab in self.tabManager.tabs {
            tab.setNoImageMode(enabled, force: true)
        }
        self.tabManager.selectedTab?.reload()
    }

    func toggleBookmarkForTabState(tabState: TabState) {
        if tabState.isBookmarked {
            self.removeBookmark(tabState)
        } else {
            self.addBookmark(tabState)
        }
    }

    func tabToolbarDidPressBookmark(tabToolbar: TabToolbarProtocol, button: UIButton) {
        guard let tab = tabManager.selectedTab,
            let _ = tab.displayURL?.absoluteString else {
                log.error("Bookmark error: No tab is selected, or no URL in tab.")
                return
        }

        toggleBookmarkForTabState(tab.tabState)
    }

    func tabToolbarDidLongPressBookmark(tabToolbar: TabToolbarProtocol, button: UIButton) {
    }

    func tabToolbarDidPressShare(tabToolbar: TabToolbarProtocol, button: UIButton) {
        if let tab = tabManager.selectedTab, url = tab.displayURL {
            let sourceView = self.navigationToolbar.shareButton
            presentActivityViewController(url, tab: tab, sourceView: sourceView.superview, sourceRect: sourceView.frame, arrowDirection: .Up)
        }
    }

    func tabToolbarDidPressHomePage(tabToolbar: TabToolbarProtocol, button: UIButton) {
        guard let tab = tabManager.selectedTab else { return }
        HomePageHelper(prefs: profile.prefs).openHomePage(inTab: tab, withNavigationController: navigationController)
    }
    
    func showBackForwardList() {
        if let backForwardList = tabManager.selectedTab?.webView?.backForwardList {
            let backForwardViewController = BackForwardListViewController(profile: profile, backForwardList: backForwardList, isPrivate: tabManager.selectedTab?.isPrivate ?? false)
            backForwardViewController.tabManager = tabManager
            backForwardViewController.bvc = self
            backForwardViewController.modalPresentationStyle = UIModalPresentationStyle.OverCurrentContext
            backForwardViewController.backForwardTransitionDelegate = BackForwardListAnimator()
            self.presentViewController(backForwardViewController, animated: true, completion: nil)
        }
    }
}

extension BrowserViewController: MenuViewControllerDelegate {
    func menuViewControllerDidDismiss(menuViewController: MenuViewController) {
        self.menuViewController = nil
        displayedPopoverController = nil
        updateDisplayedPopoverProperties = nil
    }

    func shouldCloseMenu(menuViewController: MenuViewController, forRotationToNewSize size: CGSize, forTraitCollection traitCollection: UITraitCollection) -> Bool {
        // if we're presenting in popover but we haven't got a preferred content size yet, don't dismiss, otherwise we might dismiss before we've presented
        if (traitCollection.horizontalSizeClass == .Compact && traitCollection.verticalSizeClass == .Compact) && menuViewController.preferredContentSize == CGSize.zero {
            return false
        }

        // Dismiss the menu if we are going into the background.
        let state = UIApplication.sharedApplication().applicationState
        if state != .Active {
            return true
        }

        func orientationForSize(size: CGSize) -> UIInterfaceOrientation {
            return size.height < size.width ? .LandscapeLeft : .Portrait
        }

        let currentOrientation = orientationForSize(self.view.bounds.size)
        let newOrientation = orientationForSize(size)
        let isiPhone = UI_USER_INTERFACE_IDIOM() == .Phone

        // we only want to dismiss when rotating on iPhone
        // if we're rotating from landscape to portrait then we are rotating from popover to modal
        return isiPhone && currentOrientation != newOrientation
    }
}

extension BrowserViewController: WindowCloseHelperDelegate {
    func windowCloseHelper(helper: WindowCloseHelper, didRequestToCloseTab tab: Tab) {
        tabManager.removeTab(tab)
    }
}

extension BrowserViewController: TabDelegate {

    func tab(tab: Tab, didCreateWebView webView: WKWebView) {
        webView.frame = webViewContainer.frame
        // Observers that live as long as the tab. Make sure these are all cleared
        // in willDeleteWebView below!
        webView.addObserver(self, forKeyPath: KVOEstimatedProgress, options: .New, context: nil)
        webView.addObserver(self, forKeyPath: KVOLoading, options: .New, context: nil)
        webView.addObserver(self, forKeyPath: KVOCanGoBack, options: .New, context: nil)
        webView.addObserver(self, forKeyPath: KVOCanGoForward, options: .New, context: nil)
        tab.webView?.addObserver(self, forKeyPath: KVOURL, options: .New, context: nil)

        webView.scrollView.addObserver(self.scrollController, forKeyPath: KVOContentSize, options: .New, context: nil)

        webView.UIDelegate = self

        let readerMode = ReaderMode(tab: tab)
        readerMode.delegate = self
        tab.addHelper(readerMode, name: ReaderMode.name())

        let favicons = FaviconManager(tab: tab, profile: profile)
        tab.addHelper(favicons, name: FaviconManager.name())

        // only add the logins helper if the tab is not a private browsing tab
        if !tab.isPrivate {
            let logins = LoginsHelper(tab: tab, profile: profile)
            tab.addHelper(logins, name: LoginsHelper.name())
        }

        let contextMenuHelper = ContextMenuHelper(tab: tab)
        contextMenuHelper.delegate = self
        tab.addHelper(contextMenuHelper, name: ContextMenuHelper.name())

        let errorHelper = ErrorPageHelper()
        tab.addHelper(errorHelper, name: ErrorPageHelper.name())

        let windowCloseHelper = WindowCloseHelper(tab: tab)
        windowCloseHelper.delegate = self
        tab.addHelper(windowCloseHelper, name: WindowCloseHelper.name())

        let sessionRestoreHelper = SessionRestoreHelper(tab: tab)
        sessionRestoreHelper.delegate = self
        tab.addHelper(sessionRestoreHelper, name: SessionRestoreHelper.name())

        let findInPageHelper = FindInPageHelper(tab: tab)
        findInPageHelper.delegate = self
        tab.addHelper(findInPageHelper, name: FindInPageHelper.name())

        let noImageModeHelper = NoImageModeHelper(tab: tab)
        tab.addHelper(noImageModeHelper, name: NoImageModeHelper.name())
        
        let printHelper = PrintHelper(tab: tab)
        tab.addHelper(printHelper, name: PrintHelper.name())

        let customSearchHelper = CustomSearchHelper(tab: tab)
        tab.addHelper(customSearchHelper, name: CustomSearchHelper.name())

        let openURL = {(url: NSURL) -> Void in
            self.switchToTabForURLOrOpen(url, isPrivileged: true)
        }

        let nightModeHelper = NightModeHelper(tab: tab)
        tab.addHelper(nightModeHelper, name: NightModeHelper.name())

        let spotlightHelper = SpotlightHelper(tab: tab, openURL: openURL)
        tab.addHelper(spotlightHelper, name: SpotlightHelper.name())

        tab.addHelper(LocalRequestHelper(), name: LocalRequestHelper.name())

        if AppConstants.MOZ_CONTENT_METADATA_PARSING {
            let metadataHelper = MetadataParserHelper(tab: tab, profile: profile)
            tab.addHelper(metadataHelper, name: MetadataParserHelper.name())
        }
    }

    func tab(tab: Tab, willDeleteWebView webView: WKWebView) {
        tab.cancelQueuedAlerts()

        webView.removeObserver(self, forKeyPath: KVOEstimatedProgress)
        webView.removeObserver(self, forKeyPath: KVOLoading)
        webView.removeObserver(self, forKeyPath: KVOCanGoBack)
        webView.removeObserver(self, forKeyPath: KVOCanGoForward)
        webView.scrollView.removeObserver(self.scrollController, forKeyPath: KVOContentSize)
        webView.removeObserver(self, forKeyPath: KVOURL)

        webView.UIDelegate = nil
        webView.scrollView.delegate = nil
        webView.removeFromSuperview()
    }

    private func findSnackbar(barToFind: SnackBar) -> Int? {
        let bars = snackBars.subviews
        for (index, bar) in bars.enumerate() {
            if bar === barToFind {
                return index
            }
        }
        return nil
    }

    private func updateSnackBarConstraints() {
        snackBars.snp_remakeConstraints { make in
            make.bottom.equalTo(findInPageContainer.snp_top)

            let bars = self.snackBars.subviews
            if bars.count > 0 {
                let view = bars[bars.count-1]
                make.top.equalTo(view.snp_top)
            } else {
                make.height.equalTo(0)
            }

            if traitCollection.horizontalSizeClass != .Regular {
                make.leading.trailing.equalTo(self.footer)
                self.snackBars.layer.borderWidth = 0
            } else {
                make.centerX.equalTo(self.footer)
                make.width.equalTo(SnackBarUX.MaxWidth)
                self.snackBars.layer.borderColor = UIConstants.BorderColor.CGColor
                self.snackBars.layer.borderWidth = 1
            }
        }
    }

    // This removes the bar from its superview and updates constraints appropriately
    private func finishRemovingBar(bar: SnackBar) {
        // If there was a bar above this one, we need to remake its constraints.
        if let index = findSnackbar(bar) {
            // If the bar being removed isn't on the top of the list
            let bars = snackBars.subviews
            if index < bars.count-1 {
                // Move the bar above this one
                let nextbar = bars[index+1] as! SnackBar
                nextbar.snp_updateConstraints { make in
                    // If this wasn't the bottom bar, attach to the bar below it
                    if index > 0 {
                        let bar = bars[index-1] as! SnackBar
                        nextbar.bottom = make.bottom.equalTo(bar.snp_top).constraint
                    } else {
                        // Otherwise, we attach it to the bottom of the snackbars
                        nextbar.bottom = make.bottom.equalTo(self.snackBars.snp_bottom).constraint
                    }
                }
            }
        }

        // Really remove the bar
        bar.removeFromSuperview()
    }

    private func finishAddingBar(bar: SnackBar) {
        snackBars.addSubview(bar)
        bar.snp_remakeConstraints { make in
            // If there are already bars showing, add this on top of them
            let bars = self.snackBars.subviews

            // Add the bar on top of the stack
            // We're the new top bar in the stack, so make sure we ignore ourself
            if bars.count > 1 {
                let view = bars[bars.count - 2]
                bar.bottom = make.bottom.equalTo(view.snp_top).offset(0).constraint
            } else {
                bar.bottom = make.bottom.equalTo(self.snackBars.snp_bottom).offset(0).constraint
            }
            make.leading.trailing.equalTo(self.snackBars)
        }
    }

    func showBar(bar: SnackBar, animated: Bool) {
        finishAddingBar(bar)
        updateSnackBarConstraints()

        bar.hide()
        view.layoutIfNeeded()
        UIView.animateWithDuration(animated ? 0.25 : 0, animations: { () -> Void in
            bar.show()
            self.view.layoutIfNeeded()
        })
    }

    func removeBar(bar: SnackBar, animated: Bool) {
        if let _ = findSnackbar(bar) {
            UIView.animateWithDuration(animated ? 0.25 : 0, animations: { () -> Void in
                bar.hide()
                self.view.layoutIfNeeded()
            }) { success in
                // Really remove the bar
                self.finishRemovingBar(bar)
                self.updateSnackBarConstraints()
            }
        }
    }

    func removeAllBars() {
        let bars = snackBars.subviews
        for bar in bars {
            if let bar = bar as? SnackBar {
                bar.removeFromSuperview()
            }
        }
        self.updateSnackBarConstraints()
    }

    func tab(tab: Tab, didAddSnackbar bar: SnackBar) {
        showBar(bar, animated: true)
    }

    func tab(tab: Tab, didRemoveSnackbar bar: SnackBar) {
        removeBar(bar, animated: true)
    }

    func tab(tab: Tab, didSelectFindInPageForSelection selection: String) {
        updateFindInPageVisibility(visible: true)
        findInPageBar?.text = selection
    }
}

extension BrowserViewController: HomePanelViewControllerDelegate {
    func homePanelViewController(homePanelViewController: HomePanelViewController, didSelectURL url: NSURL, visitType: VisitType) {
        finishEditingAndSubmit(url, visitType: visitType)
    }

    func homePanelViewController(homePanelViewController: HomePanelViewController, didSelectPanel panel: Int) {
        if AboutUtils.isAboutHomeURL(tabManager.selectedTab?.url) {
            tabManager.selectedTab?.webView?.evaluateJavaScript("history.replaceState({}, '', '#panel=\(panel)')", completionHandler: nil)
        }
    }

    func homePanelViewControllerDidRequestToCreateAccount(homePanelViewController: HomePanelViewController) {
        presentSignInViewController() // TODO UX Right now the flow for sign in and create account is the same
    }

    func homePanelViewControllerDidRequestToSignIn(homePanelViewController: HomePanelViewController) {
        presentSignInViewController() // TODO UX Right now the flow for sign in and create account is the same
    }
}

extension BrowserViewController: SearchViewControllerDelegate {
    func searchViewController(searchViewController: SearchViewController, didSelectURL url: NSURL) {
        finishEditingAndSubmit(url, visitType: VisitType.Typed)
    }

    func presentSearchSettingsController() {
        let settingsNavigationController = SearchSettingsTableViewController()
        settingsNavigationController.model = self.profile.searchEngines

        let navController = UINavigationController(rootViewController: settingsNavigationController)

        self.presentViewController(navController, animated: true, completion: nil)
    }
}

extension BrowserViewController: TabManagerDelegate {
    func tabManager(tabManager: TabManager, didSelectedTabChange selected: Tab?, previous: Tab?) {
        // Remove the old accessibilityLabel. Since this webview shouldn't be visible, it doesn't need it
        // and having multiple views with the same label confuses tests.
        if let wv = previous?.webView {
            removeOpenInView()
            wv.endEditing(true)
            wv.accessibilityLabel = nil
            wv.accessibilityElementsHidden = true
            wv.accessibilityIdentifier = nil
            wv.removeFromSuperview()
        }

        if let tab = selected, webView = tab.webView {
            updateURLBarDisplayURL(tab)

            if tab.isPrivate {
                readerModeCache = MemoryReaderModeCache.sharedInstance
                applyTheme(Theme.PrivateMode)
            } else {
                readerModeCache = DiskReaderModeCache.sharedInstance
                applyTheme(Theme.NormalMode)
            }
            if let privateModeButton = topTabsViewController?.privateModeButton where previous != nil && previous?.isPrivate != tab.isPrivate {
                privateModeButton.setSelected(tab.isPrivate, animated: true)
            }
            ReaderModeHandlers.readerModeCache = readerModeCache

            scrollController.tab = selected
            webViewContainer.addSubview(webView)
            webView.snp_makeConstraints { make in
                make.top.equalTo(webViewContainerToolbar.snp_bottom)
                make.left.right.bottom.equalTo(self.webViewContainer)
            }
            webView.accessibilityLabel = NSLocalizedString("Web content", comment: "Accessibility label for the main web content view")
            webView.accessibilityIdentifier = "contentView"
            webView.accessibilityElementsHidden = false

            if let url = webView.URL?.absoluteString {
                // Don't bother fetching bookmark state for about/sessionrestore and about/home.
                if AboutUtils.isAboutURL(webView.URL) {
                    // Indeed, because we don't show the toolbar at all, don't even blank the star.
                } else {
                    profile.bookmarks.modelFactory >>== { [weak tab] in
                        $0.isBookmarked(url)
                            .uponQueue(dispatch_get_main_queue()) {
                            guard let isBookmarked = $0.successValue else {
                                log.error("Error getting bookmark status: \($0.failureValue).")
                                return
                            }

                            tab?.isBookmarked = isBookmarked
                        }
                    }
                }
            } else {
                // The web view can go gray if it was zombified due to memory pressure.
                // When this happens, the URL is nil, so try restoring the page upon selection.
                tab.reload()
            }
        }

        if let selected = selected, previous = previous where selected.isPrivate != previous.isPrivate {
            updateTabCountUsingTabManager(tabManager)
        }

        removeAllBars()
        if let bars = selected?.bars {
            for bar in bars {
                showBar(bar, animated: true)
            }
        }

        updateFindInPageVisibility(visible: false)

        navigationToolbar.updateReloadStatus(selected?.loading ?? false)
        navigationToolbar.updateBackStatus(selected?.canGoBack ?? false)
        navigationToolbar.updateForwardStatus(selected?.canGoForward ?? false)
        self.urlBar.updateProgressBar(Float(selected?.estimatedProgress ?? 0))

        if let readerMode = selected?.getHelper(name: ReaderMode.name()) as? ReaderMode {
            urlBar.updateReaderModeState(readerMode.state)
            if readerMode.state == .Active {
                showReaderModeBar(animated: false)
            } else {
                hideReaderModeBar(animated: false)
            }
        } else {
            urlBar.updateReaderModeState(ReaderModeState.Unavailable)
        }

        updateInContentHomePanel(selected?.url)
    }

    func tabManager(tabManager: TabManager, didCreateTab tab: Tab) {
    }

    func tabManager(tabManager: TabManager, didAddTab tab: Tab) {
        // If we are restoring tabs then we update the count once at the end
        if !tabManager.isRestoring {
            updateTabCountUsingTabManager(tabManager)
        }
        tab.tabDelegate = self
        tab.appStateDelegate = self
    }

    func tabManager(tabManager: TabManager, didRemoveTab tab: Tab) {
        updateTabCountUsingTabManager(tabManager)
        // tabDelegate is a weak ref (and the tab's webView may not be destroyed yet)
        // so we don't expcitly unset it.

        if let url = tab.url where !AboutUtils.isAboutURL(tab.url) && !tab.isPrivate {
            profile.recentlyClosedTabs.addTab(url, title: tab.title, faviconURL: tab.displayFavicon?.url)
        }
    }

    func tabManagerDidAddTabs(tabManager: TabManager) {
        updateTabCountUsingTabManager(tabManager)
    }

    func tabManagerDidRestoreTabs(tabManager: TabManager) {
        updateTabCountUsingTabManager(tabManager)
    }
    
    func tabManagerDidRemoveAllTabs(tabManager: TabManager, toast: ButtonToast?) {
        guard !tabTrayController.privateMode else {
            return
        }
        
        if let undoToast = toast {
            let time = dispatch_time(dispatch_time_t(DISPATCH_TIME_NOW), Int64(ButtonToastUX.ToastDelay * Double(NSEC_PER_SEC)))
            dispatch_after(time, dispatch_get_main_queue()) {
                self.view.addSubview(undoToast)
                undoToast.snp_makeConstraints { make in
                    make.left.right.equalTo(self.view)
                    make.bottom.equalTo(self.webViewContainer)
                }
                undoToast.showToast()
            }
        }
    }

    private func updateTabCountUsingTabManager(tabManager: TabManager, animated: Bool = true) {
        if let selectedTab = tabManager.selectedTab {
            let count = selectedTab.isPrivate ? tabManager.privateTabs.count : tabManager.normalTabs.count
            urlBar.updateTabCount(max(count, 1), animated: animated)
            topTabsViewController?.updateTabCount(max(count, 1), animated: animated)
        }
    }
}

extension BrowserViewController: WKNavigationDelegate {
    func webView(webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if tabManager.selectedTab?.webView !== webView {
            return
        }

        updateFindInPageVisibility(visible: false)

        // If we are going to navigate to a new page, hide the reader mode button. Unless we
        // are going to a about:reader page. Then we keep it on screen: it will change status
        // (orange color) as soon as the page has loaded.
        if let url = webView.URL {
            if !ReaderModeUtils.isReaderModeURL(url) {
                urlBar.updateReaderModeState(ReaderModeState.Unavailable)
                hideReaderModeBar(animated: false)
            }

            // remove the open in overlay view if it is present
            removeOpenInView()
        }
    }

    // Recognize an Apple Maps URL. This will trigger the native app. But only if a search query is present. Otherwise
    // it could just be a visit to a regular page on maps.apple.com.
    private func isAppleMapsURL(url: NSURL) -> Bool {
        if url.scheme == "http" || url.scheme == "https" {
            if url.host == "maps.apple.com" && url.query != nil {
                return true
            }
        }
        return false
    }

    // Recognize a iTunes Store URL. These all trigger the native apps. Note that appstore.com and phobos.apple.com
    // used to be in this list. I have removed them because they now redirect to itunes.apple.com. If we special case
    // them then iOS will actually first open Safari, which then redirects to the app store. This works but it will
    // leave a 'Back to Safari' button in the status bar, which we do not want.
    private func isStoreURL(url: NSURL) -> Bool {
        if url.scheme == "http" || url.scheme == "https" {
            if url.host == "itunes.apple.com" {
                return true
            }
        }
        return false
    }

    // This is the place where we decide what to do with a new navigation action. There are a number of special schemes
    // and http(s) urls that need to be handled in a different way. All the logic for that is inside this delegate
    // method.

    func webView(webView: WKWebView, decidePolicyForNavigationAction navigationAction: WKNavigationAction, decisionHandler: (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.URL else {
            decisionHandler(WKNavigationActionPolicy.Cancel)
            return
        }

        // Fixes 1261457 - Rich text editor fails because requests to about:blank are blocked
        if url.scheme == "about" && url.resourceSpecifier == "blank" {
            decisionHandler(WKNavigationActionPolicy.Allow)
            return
        }

        if !navigationAction.isAllowed && navigationAction.navigationType != .BackForward {
            print("\(navigationAction.isAllowed) \(navigationAction.navigationType == .BackForward) \(navigationAction.request.URL)")
            log.warning("Denying unprivileged request: \(navigationAction.request)")
            decisionHandler(WKNavigationActionPolicy.Cancel)
            return
        }

        // First special case are some schemes that are about Calling. We prompt the user to confirm this action. This
        // gives us the exact same behaviour as Safari.

        if url.scheme == "tel" || url.scheme == "facetime" || url.scheme == "facetime-audio" {
            if let phoneNumber = url.resourceSpecifier?.stringByRemovingPercentEncoding where !phoneNumber.isEmpty {
                let formatter = PhoneNumberFormatter()
                let formattedPhoneNumber = formatter.formatPhoneNumber(phoneNumber)
                let alert = UIAlertController(title: formattedPhoneNumber, message: nil, preferredStyle: UIAlertControllerStyle.Alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment:"Label for Cancel button"), style: UIAlertActionStyle.Cancel, handler: nil))
                alert.addAction(UIAlertAction(title: NSLocalizedString("Call", comment:"Alert Call Button"), style: UIAlertActionStyle.Default, handler: { (action: UIAlertAction!) in
                    UIApplication.sharedApplication().openURL(url)
                }))
                presentViewController(alert, animated: true, completion: nil)
            }
            decisionHandler(WKNavigationActionPolicy.Cancel)
            return
        }

        // Second special case are a set of URLs that look like regular http links, but should be handed over to iOS
        // instead of being loaded in the webview. Note that there is no point in calling canOpenURL() here, because
        // iOS will always say yes. TODO Is this the same as isWhitelisted?

        if isAppleMapsURL(url) || isStoreURL(url) {
            UIApplication.sharedApplication().openURL(url)
            decisionHandler(WKNavigationActionPolicy.Cancel)
            return
        }

        // This is the normal case, opening a http or https url, which we handle by loading them in this WKWebView. We
        // always allow this. Additionally, data URIs are also handled just like normal web pages.

        if url.scheme == "http" || url.scheme == "https" || url.scheme == "data" {
            if navigationAction.navigationType == .LinkActivated {
                resetSpoofedUserAgentIfRequired(webView, newURL: url)
            } else if navigationAction.navigationType == .BackForward {
                restoreSpoofedUserAgentIfRequired(webView, newRequest: navigationAction.request)
            }
            decisionHandler(WKNavigationActionPolicy.Allow)
            return
        }

        // Default to calling openURL(). What this does depends on the iOS version. On iOS 8, it will just work without
        // prompting. On iOS9, depending on the scheme, iOS will prompt: "Firefox" wants to open "Twitter". It will ask
        // every time. There is no way around this prompt. (TODO Confirm this is true by adding them to the Info.plist)

        let openedURL = UIApplication.sharedApplication().openURL(url)
        if !openedURL {
            let alert = UIAlertController(title: Strings.UnableToOpenURLErrorTitle, message: Strings.UnableToOpenURLError, preferredStyle: .Alert)
            alert.addAction(UIAlertAction(title: UIConstants.OKString, style: UIAlertActionStyle.Default, handler: nil))
            self.presentViewController(alert, animated: true, completion: nil)
        }
        decisionHandler(WKNavigationActionPolicy.Cancel)
    }

    func webView(webView: WKWebView, didReceiveAuthenticationChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {

        // If this is a certificate challenge, see if the certificate has previously been
        // accepted by the user.
        let origin = "\(challenge.protectionSpace.host):\(challenge.protectionSpace.port)"
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           let cert = SecTrustGetCertificateAtIndex(trust, 0) where profile.certStore.containsCertificate(cert, forOrigin: origin) {
            completionHandler(NSURLSessionAuthChallengeDisposition.UseCredential, NSURLCredential(forTrust: trust))
            return
        }

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest ||
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodNTLM,
              let tab = tabManager[webView] else {
            completionHandler(NSURLSessionAuthChallengeDisposition.PerformDefaultHandling, nil)
            return
        }

        // The challenge may come from a background tab, so ensure it's the one visible.
        tabManager.selectTab(tab)

        let loginsHelper = tab.getHelper(name: LoginsHelper.name()) as? LoginsHelper
        Authenticator.handleAuthRequest(self, challenge: challenge, loginsHelper: loginsHelper).uponQueue(dispatch_get_main_queue()) { res in
            if let credentials = res.successValue {
                completionHandler(.UseCredential, credentials.credentials)
            } else {
                completionHandler(NSURLSessionAuthChallengeDisposition.RejectProtectionSpace, nil)
            }
        }
    }

    func webView(webView: WKWebView, didCommitNavigation navigation: WKNavigation!) {
        guard let tab = tabManager[webView] else { return }

        tab.url = webView.URL

        if tabManager.selectedTab === tab {
            updateUIForReaderHomeStateForTab(tab)
            appDidUpdateState(getCurrentAppState())
        }
    }

    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        let tab: Tab! = tabManager[webView]
        tabManager.expireSnackbars()

        if let url = webView.URL where !ErrorPageHelper.isErrorPageURL(url) && !AboutUtils.isAboutHomeURL(url) {
            tab.lastExecutedTime = NSDate.now()

            if navigation == nil {
                log.warning("Implicitly unwrapped optional navigation was nil.")
            }

            postLocationChangeNotificationForTab(tab, navigation: navigation)

            // Fire the readability check. This is here and not in the pageShow event handler in ReaderMode.js anymore
            // because that event wil not always fire due to unreliable page caching. This will either let us know that
            // the currently loaded page can be turned into reading mode or if the page already is in reading mode. We
            // ignore the result because we are being called back asynchronous when the readermode status changes.
            webView.evaluateJavaScript("\(ReaderModeNamespace).checkReadability()", completionHandler: nil)
        }

        if tab === tabManager.selectedTab {
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
            // must be followed by LayoutChanged, as ScreenChanged will make VoiceOver
            // cursor land on the correct initial element, but if not followed by LayoutChanged,
            // VoiceOver will sometimes be stuck on the element, not allowing user to move
            // forward/backward. Strange, but LayoutChanged fixes that.
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
        } else {
            // To Screenshot a tab that is hidden we must add the webView,
            // then wait enough time for the webview to render.
            if let webView =  tab.webView {
                view.insertSubview(webView, atIndex: 0)
                let time = dispatch_time(DISPATCH_TIME_NOW, Int64(500 * NSEC_PER_MSEC))
                dispatch_after(time, dispatch_get_main_queue()) {
                    self.screenshotHelper.takeScreenshot(tab)
                    if webView.superview == self.view {
                        webView.removeFromSuperview()
                    }
                }
            }
        }

        // Remember whether or not a desktop site was requested
        tab.desktopSite = webView.customUserAgent?.isEmpty == false
    }

    private func addViewForOpenInHelper(openInHelper: OpenInHelper) {
        guard let view = openInHelper.openInView else { return }
        webViewContainerToolbar.addSubview(view)
        webViewContainerToolbar.snp_updateConstraints { make in
            make.height.equalTo(OpenInViewUX.ViewHeight)
        }
        view.snp_makeConstraints { make in
            make.edges.equalTo(webViewContainerToolbar)
        }

        self.openInHelper = openInHelper
    }

    private func removeOpenInView() {
        guard let _ = self.openInHelper else { return }
        webViewContainerToolbar.subviews.forEach { $0.removeFromSuperview() }

        webViewContainerToolbar.snp_updateConstraints { make in
            make.height.equalTo(0)
        }

        self.openInHelper = nil
    }

    private func postLocationChangeNotificationForTab(tab: Tab, navigation: WKNavigation?) {
        let notificationCenter = NSNotificationCenter.defaultCenter()
        var info = [NSObject: AnyObject]()
        info["url"] = tab.displayURL
        info["title"] = tab.title
        if let visitType = self.getVisitTypeForTab(tab, navigation: navigation)?.rawValue {
            info["visitType"] = visitType
        }
        info["isPrivate"] = tab.isPrivate
        notificationCenter.postNotificationName(NotificationOnLocationChange, object: self, userInfo: info)
    }
}

/// List of schemes that are allowed to open a popup window
private let SchemesAllowedToOpenPopups = ["http", "https", "javascript", "data"]

extension BrowserViewController: WKUIDelegate {
    func webView(webView: WKWebView, createWebViewWithConfiguration configuration: WKWebViewConfiguration, forNavigationAction navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let parentTab = tabManager[webView] else { return nil }

        if !navigationAction.isAllowed {
            log.warning("Denying unprivileged request: \(navigationAction.request)")
            return nil
        }

        if let currentTab = tabManager.selectedTab {
            screenshotHelper.takeScreenshot(currentTab)
        }

        // If the page uses window.open() or target="_blank", open the page in a new tab.
        let newTab = tabManager.addTab(navigationAction.request, configuration: configuration, afterTab: parentTab, isPrivate: parentTab.isPrivate)
        tabManager.selectTab(newTab)

        // If the page we just opened has a bad scheme, we return nil here so that JavaScript does not
        // get a reference to it which it can return from window.open() - this will end up as a
        // CFErrorHTTPBadURL being presented.
        guard let scheme = navigationAction.request.URL?.scheme?.lowercaseString where SchemesAllowedToOpenPopups.contains(scheme) else {
            return nil
        }

        return newTab.webView
    }

    private func canDisplayJSAlertForWebView(webView: WKWebView) -> Bool {
        // Only display a JS Alert if we are selected and there isn't anything being shown
        return (tabManager.selectedTab?.webView == webView ?? false) && (self.presentedViewController == nil)
    }

    func webView(webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: () -> Void) {
        let messageAlert = MessageAlert(message: message, frame: frame, completionHandler: completionHandler)
        if canDisplayJSAlertForWebView(webView) {
            presentViewController(messageAlert.alertController(), animated: true, completion: nil)
        } else if let promptingTab = tabManager[webView] {
            promptingTab.queueJavascriptAlertPrompt(messageAlert)
        } else {
            // This should never happen since an alert needs to come from a web view but just in case call the handler
            // since not calling it will result in a runtime exception.
            completionHandler()
        }
    }

    func webView(webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: (Bool) -> Void) {
        let confirmAlert = ConfirmPanelAlert(message: message, frame: frame, completionHandler: completionHandler)
        if canDisplayJSAlertForWebView(webView) {
            presentViewController(confirmAlert.alertController(), animated: true, completion: nil)
        } else if let promptingTab = tabManager[webView] {
            promptingTab.queueJavascriptAlertPrompt(confirmAlert)
        } else {
            completionHandler(false)
        }
    }

    func webView(webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: (String?) -> Void) {
        let textInputAlert = TextInputAlert(message: prompt, frame: frame, completionHandler: completionHandler, defaultText: defaultText)
        if canDisplayJSAlertForWebView(webView) {
            presentViewController(textInputAlert.alertController(), animated: true, completion: nil)
        } else if let promptingTab = tabManager[webView] {
            promptingTab.queueJavascriptAlertPrompt(textInputAlert)
        } else {
            completionHandler(nil)
        }
    }

    /// Invoked when an error occurs while starting to load data for the main frame.
    func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: NSError) {
        // Ignore the "Frame load interrupted" error that is triggered when we cancel a request
        // to open an external application and hand it over to UIApplication.openURL(). The result
        // will be that we switch to the external app, for example the app store, while keeping the
        // original web page in the tab instead of replacing it with an error page.
        if error.domain == "WebKitErrorDomain" && error.code == 102 {
            return
        }

        if checkIfWebContentProcessHasCrashed(webView, error: error) {
            return
        }

        if error.code == Int(CFNetworkErrors.CFURLErrorCancelled.rawValue) {
            if let tab = tabManager[webView] where tab === tabManager.selectedTab {
                urlBar.currentURL = tab.displayURL
            }
            return
        }

        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? NSURL {
            ErrorPageHelper().showPage(error, forUrl: url, inWebView: webView)

            // If the local web server isn't working for some reason (Firefox cellular data is
            // disabled in settings, for example), we'll fail to load the session restore URL.
            // We rely on loading that page to get the restore callback to reset the restoring
            // flag, so if we fail to load that page, reset it here.
            if AboutUtils.getAboutComponent(url) == "sessionrestore" {
                tabManager.tabs.filter { $0.webView == webView }.first?.restoring = false
            }
        }
    }

    private func checkIfWebContentProcessHasCrashed(webView: WKWebView, error: NSError) -> Bool {
        if error.code == WKErrorCode.WebContentProcessTerminated.rawValue && error.domain == "WebKitErrorDomain" {
            log.debug("WebContent process has crashed. Trying to reloadFromOrigin to restart it.")
            webView.reloadFromOrigin()
            return true
        }

        return false
    }

    func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void) {
        let helperForURL = OpenIn.helperForResponse(navigationResponse.response)
        if navigationResponse.canShowMIMEType {
            if let openInHelper = helperForURL {
                addViewForOpenInHelper(openInHelper)
            }
            decisionHandler(WKNavigationResponsePolicy.Allow)
            return
        }

        guard var openInHelper = helperForURL else {
            let error = NSError(domain: ErrorPageHelper.MozDomain, code: Int(ErrorPageHelper.MozErrorDownloadsNotEnabled), userInfo: [NSLocalizedDescriptionKey: Strings.UnableToDownloadError])
            ErrorPageHelper().showPage(error, forUrl: navigationResponse.response.URL!, inWebView: webView)
            return decisionHandler(WKNavigationResponsePolicy.Allow)
        }
        
        if openInHelper.openInView == nil {
            openInHelper.openInView = navigationToolbar.shareButton
        }

        openInHelper.open()
        decisionHandler(WKNavigationResponsePolicy.Cancel)
    }

    func webViewDidClose(webView: WKWebView) {
        if let tab = tabManager[webView] {
            self.tabManager.removeTab(tab)
        }
    }
}

extension BrowserViewController: ReaderModeDelegate {
    func readerMode(readerMode: ReaderMode, didChangeReaderModeState state: ReaderModeState, forTab tab: Tab) {
        // If this reader mode availability state change is for the tab that we currently show, then update
        // the button. Otherwise do nothing and the button will be updated when the tab is made active.
        if tabManager.selectedTab === tab {
            urlBar.updateReaderModeState(state)
        }
    }

    func readerMode(readerMode: ReaderMode, didDisplayReaderizedContentForTab tab: Tab) {
        self.showReaderModeBar(animated: true)
        tab.showContent(true)
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension BrowserViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerDidDismissPopover(popoverPresentationController: UIPopoverPresentationController) {
        displayedPopoverController = nil
        updateDisplayedPopoverProperties = nil
    }
}

extension BrowserViewController: UIAdaptivePresentationControllerDelegate {
    // Returning None here makes sure that the Popover is actually presented as a Popover and
    // not as a full-screen modal, which is the default on compact device classes.
    func adaptivePresentationStyleForPresentationController(controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.None
    }
}

// MARK: - ReaderModeStyleViewControllerDelegate

extension BrowserViewController: ReaderModeStyleViewControllerDelegate {
    func readerModeStyleViewController(readerModeStyleViewController: ReaderModeStyleViewController, didConfigureStyle style: ReaderModeStyle) {
        // Persist the new style to the profile
        let encodedStyle: [String:AnyObject] = style.encode()
        profile.prefs.setObject(encodedStyle, forKey: ReaderModeProfileKeyStyle)
        // Change the reader mode style on all tabs that have reader mode active
        for tabIndex in 0..<tabManager.count {
            if let tab = tabManager[tabIndex] {
                if let readerMode = tab.getHelper(name: "ReaderMode") as? ReaderMode {
                    if readerMode.state == ReaderModeState.Active {
                        readerMode.style = style
                    }
                }
            }
        }
    }
}

extension BrowserViewController {
    func updateReaderModeBar() {
        if let readerModeBar = readerModeBar {
            if let tab = self.tabManager.selectedTab where tab.isPrivate {
                readerModeBar.applyTheme(Theme.PrivateMode)
            } else {
                readerModeBar.applyTheme(Theme.NormalMode)
            }
            if let url = self.tabManager.selectedTab?.displayURL?.absoluteString, result = profile.readingList?.getRecordWithURL(url) {
                if let successValue = result.successValue, record = successValue {
                    readerModeBar.unread = record.unread
                    readerModeBar.added = true
                } else {
                    readerModeBar.unread = true
                    readerModeBar.added = false
                }
            } else {
                readerModeBar.unread = true
                readerModeBar.added = false
            }
        }
    }

    func showReaderModeBar(animated animated: Bool) {
        if self.readerModeBar == nil {
            let readerModeBar = ReaderModeBarView(frame: CGRectZero)
            readerModeBar.delegate = self
            view.insertSubview(readerModeBar, belowSubview: header)
            self.readerModeBar = readerModeBar
        }

        updateReaderModeBar()

        self.updateViewConstraints()
    }

    func hideReaderModeBar(animated animated: Bool) {
        if let readerModeBar = self.readerModeBar {
            readerModeBar.removeFromSuperview()
            self.readerModeBar = nil
            self.updateViewConstraints()
        }
    }

    /// There are two ways we can enable reader mode. In the simplest case we open a URL to our internal reader mode
    /// and be done with it. In the more complicated case, reader mode was already open for this page and we simply
    /// navigated away from it. So we look to the left and right in the BackForwardList to see if a readerized version
    /// of the current page is there. And if so, we go there.

    func enableReaderMode() {
        guard let tab = tabManager.selectedTab, webView = tab.webView else { return }

        let backList = webView.backForwardList.backList
        let forwardList = webView.backForwardList.forwardList

        guard let currentURL = webView.backForwardList.currentItem?.URL, let readerModeURL = ReaderModeUtils.encodeURL(currentURL) else { return }

        if backList.count > 1 && backList.last?.URL == readerModeURL {
            webView.goToBackForwardListItem(backList.last!)
        } else if forwardList.count > 0 && forwardList.first?.URL == readerModeURL {
            webView.goToBackForwardListItem(forwardList.first!)
        } else {
            // Store the readability result in the cache and load it. This will later move to the ReadabilityHelper.
            webView.evaluateJavaScript("\(ReaderModeNamespace).readerize()", completionHandler: { (object, error) -> Void in
                if let readabilityResult = ReadabilityResult(object: object) {
                    do {
                        try self.readerModeCache.put(currentURL, readabilityResult)
                    } catch _ {
                    }
                    if let nav = webView.loadRequest(PrivilegedRequest(URL: readerModeURL)) {
                        self.ignoreNavigationInTab(tab, navigation: nav)
                    }
                }
            })
        }
    }

    /// Disabling reader mode can mean two things. In the simplest case we were opened from the reading list, which
    /// means that there is nothing in the BackForwardList except the internal url for the reader mode page. In that
    /// case we simply open a new page with the original url. In the more complicated page, the non-readerized version
    /// of the page is either to the left or right in the BackForwardList. If that is the case, we navigate there.

    func disableReaderMode() {
        if let tab = tabManager.selectedTab,
            let webView = tab.webView {
            let backList = webView.backForwardList.backList
            let forwardList = webView.backForwardList.forwardList

            if let currentURL = webView.backForwardList.currentItem?.URL {
                if let originalURL = ReaderModeUtils.decodeURL(currentURL) {
                    if backList.count > 1 && backList.last?.URL == originalURL {
                        webView.goToBackForwardListItem(backList.last!)
                    } else if forwardList.count > 0 && forwardList.first?.URL == originalURL {
                        webView.goToBackForwardListItem(forwardList.first!)
                    } else {
                        if let nav = webView.loadRequest(NSURLRequest(URL: originalURL)) {
                            self.ignoreNavigationInTab(tab, navigation: nav)
                        }
                    }
                }
            }
        }
    }

    func SELDynamicFontChanged(notification: NSNotification) {
        guard notification.name == NotificationDynamicFontChanged else { return }

        var readerModeStyle = DefaultReaderModeStyle
        if let dict = profile.prefs.dictionaryForKey(ReaderModeProfileKeyStyle) {
            if let style = ReaderModeStyle(dict: dict) {
                readerModeStyle = style
            }
        }
        readerModeStyle.fontSize = ReaderModeFontSize.defaultSize
        self.readerModeStyleViewController(ReaderModeStyleViewController(), didConfigureStyle: readerModeStyle)
    }
}

extension BrowserViewController: ReaderModeBarViewDelegate {
    func readerModeBar(readerModeBar: ReaderModeBarView, didSelectButton buttonType: ReaderModeBarButtonType) {
        switch buttonType {
        case .Settings:
            if let readerMode = tabManager.selectedTab?.getHelper(name: "ReaderMode") as? ReaderMode where readerMode.state == ReaderModeState.Active {
                var readerModeStyle = DefaultReaderModeStyle
                if let dict = profile.prefs.dictionaryForKey(ReaderModeProfileKeyStyle) {
                    if let style = ReaderModeStyle(dict: dict) {
                        readerModeStyle = style
                    }
                }

                let readerModeStyleViewController = ReaderModeStyleViewController()
                readerModeStyleViewController.delegate = self
                readerModeStyleViewController.readerModeStyle = readerModeStyle
                readerModeStyleViewController.modalPresentationStyle = UIModalPresentationStyle.Popover

                let setupPopover = { [unowned self] in
                    if let popoverPresentationController = readerModeStyleViewController.popoverPresentationController {
                        popoverPresentationController.backgroundColor = UIColor.whiteColor()
                        popoverPresentationController.delegate = self
                        popoverPresentationController.sourceView = readerModeBar
                        popoverPresentationController.sourceRect = CGRect(x: readerModeBar.frame.width/2, y: UIConstants.ToolbarHeight, width: 1, height: 1)
                        popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirection.Up
                    }
                }

                setupPopover()

                if readerModeStyleViewController.popoverPresentationController != nil {
                    displayedPopoverController = readerModeStyleViewController
                    updateDisplayedPopoverProperties = setupPopover
                }

                self.presentViewController(readerModeStyleViewController, animated: true, completion: nil)
            }

        case .MarkAsRead:
            if let url = self.tabManager.selectedTab?.displayURL?.absoluteString, result = profile.readingList?.getRecordWithURL(url) {
                if let successValue = result.successValue, record = successValue {
                    profile.readingList?.updateRecord(record, unread: false) // TODO Check result, can this fail?
                    readerModeBar.unread = false
                }
            }

        case .MarkAsUnread:
            if let url = self.tabManager.selectedTab?.displayURL?.absoluteString, result = profile.readingList?.getRecordWithURL(url) {
                if let successValue = result.successValue, record = successValue {
                    profile.readingList?.updateRecord(record, unread: true) // TODO Check result, can this fail?
                    readerModeBar.unread = true
                }
            }

        case .AddToReadingList:
            if let tab = tabManager.selectedTab,
               let rawURL = tab.url where ReaderModeUtils.isReaderModeURL(rawURL),
               let url = ReaderModeUtils.decodeURL(rawURL),
               let absoluteString = url.absoluteString {
                    profile.readingList?.createRecordWithURL(absoluteString, title: tab.title ?? "", addedBy: UIDevice.currentDevice().name) // TODO Check result, can this fail?
                    readerModeBar.added = true
                    readerModeBar.unread = true
            }

        case .RemoveFromReadingList:
            if let url = self.tabManager.selectedTab?.displayURL?.absoluteString,
               let result = profile.readingList?.getRecordWithURL(url),
               let successValue = result.successValue,
               let record = successValue {
                    profile.readingList?.deleteRecord(record) // TODO Check result, can this fail?
                    readerModeBar.added = false
                    readerModeBar.unread = false
            }
        }
    }
}

extension BrowserViewController: IntroViewControllerDelegate {
    func presentIntroViewController(force: Bool = false) -> Bool {
        if force || profile.prefs.intForKey(IntroViewControllerSeenProfileKey) == nil {
            let introViewController = IntroViewController()
            introViewController.delegate = self
            // On iPad we present it modally in a controller
            if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
                introViewController.preferredContentSize = CGSize(width: IntroViewControllerUX.Width, height: IntroViewControllerUX.Height)
                introViewController.modalPresentationStyle = UIModalPresentationStyle.FormSheet
            }
            presentViewController(introViewController, animated: true) {
                self.profile.prefs.setInt(1, forKey: IntroViewControllerSeenProfileKey)
                // On first run (and forced) open up the homepage in the background.
                let state = self.getCurrentAppState()
                if let homePageURL = HomePageAccessors.getHomePage(state), tab = self.tabManager.selectedTab where DeviceInfo.hasConnectivity() {
                    tab.loadRequest(NSURLRequest(URL: homePageURL))
                }
            }

            return true
        }

        return false
    }

    func introViewControllerDidFinish(introViewController: IntroViewController) {
        introViewController.dismissViewControllerAnimated(true) { finished in
            if self.navigationController?.viewControllers.count > 1 {
                self.navigationController?.popToRootViewControllerAnimated(true)
            }
        }
    }

    func presentSignInViewController() {
        // Show the settings page if we have already signed in. If we haven't then show the signin page
        let vcToPresent: UIViewController
        if profile.hasAccount() {
            let settingsTableViewController = AppSettingsTableViewController()
            settingsTableViewController.profile = profile
            settingsTableViewController.tabManager = tabManager
            vcToPresent = settingsTableViewController
        } else {
            let signInVC = FxAContentViewController()
            signInVC.delegate = self
            signInVC.url = profile.accountConfiguration.signInURL
            signInVC.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Cancel, target: self, action: #selector(BrowserViewController.dismissSignInViewController))
            vcToPresent = signInVC
        }

        let settingsNavigationController = SettingsNavigationController(rootViewController: vcToPresent)
		settingsNavigationController.modalPresentationStyle = .FormSheet
        self.presentViewController(settingsNavigationController, animated: true, completion: nil)
    }

    func dismissSignInViewController() {
        self.dismissViewControllerAnimated(true, completion: nil)
    }

    func introViewControllerDidRequestToLogin(introViewController: IntroViewController) {
        introViewController.dismissViewControllerAnimated(true, completion: { () -> Void in
            self.presentSignInViewController()
        })
    }
}

extension BrowserViewController: FxAContentViewControllerDelegate {
    func contentViewControllerDidSignIn(viewController: FxAContentViewController, data: JSON) -> Void {
        if data["keyFetchToken"].asString == nil || data["unwrapBKey"].asString == nil {
            // The /settings endpoint sends a partial "login"; ignore it entirely.
            log.debug("Ignoring didSignIn with keyFetchToken or unwrapBKey missing.")
            return
        }

        // TODO: Error handling.
        let account = FirefoxAccount.fromConfigurationAndJSON(profile.accountConfiguration, data: data)!
        profile.setAccount(account)
        if let account = self.profile.getAccount() {
            account.advance()
        }
        self.dismissViewControllerAnimated(true, completion: nil)
    }

    func contentViewControllerDidCancel(viewController: FxAContentViewController) {
        log.info("Did cancel out of FxA signin")
        self.dismissViewControllerAnimated(true, completion: nil)
    }
}

extension BrowserViewController: ContextMenuHelperDelegate {
    func contextMenuHelper(contextMenuHelper: ContextMenuHelper, didLongPressElements elements: ContextMenuHelper.Elements, gestureRecognizer: UILongPressGestureRecognizer) {
        // locationInView can return (0, 0) when the long press is triggered in an invalid page
        // state (e.g., long pressing a link before the document changes, then releasing after a
        // different page loads).
        let touchPoint = gestureRecognizer.locationInView(view)
        guard touchPoint != CGPointZero else { return }

        let touchSize = CGSizeMake(0, 16)

        let actionSheetController = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.ActionSheet)
        var dialogTitle: String?

        if let url = elements.link, currentTab = tabManager.selectedTab {
            dialogTitle = url.absoluteString
            let isPrivate = currentTab.isPrivate
            if !isPrivate {
                let newTabTitle = NSLocalizedString("Open in New Tab", comment: "Context menu item for opening a link in a new tab")
                let openNewTabAction =  UIAlertAction(title: newTabTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) in
                    self.scrollController.showToolbars(animated: !self.scrollController.toolbarsShowing, completion: { _ in
                        self.tabManager.addTab(NSURLRequest(URL: url), afterTab: currentTab)
                    })
                }
                actionSheetController.addAction(openNewTabAction)
            }

            let openNewPrivateTabTitle = NSLocalizedString("Open in New Private Tab", tableName: "PrivateBrowsing", comment: "Context menu option for opening a link in a new private tab")
            let openNewPrivateTabAction =  UIAlertAction(title: openNewPrivateTabTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) in
                self.scrollController.showToolbars(animated: !self.scrollController.toolbarsShowing, completion: { _ in
                    self.tabManager.addTab(NSURLRequest(URL: url), afterTab: currentTab, isPrivate: true)
                })
            }
            actionSheetController.addAction(openNewPrivateTabAction)

            let copyTitle = NSLocalizedString("Copy Link", comment: "Context menu item for copying a link URL to the clipboard")
            let copyAction = UIAlertAction(title: copyTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) -> Void in
                let pasteBoard = UIPasteboard.generalPasteboard()
                pasteBoard.URL = url
            }
            actionSheetController.addAction(copyAction)

            let shareTitle = NSLocalizedString("Share Link", comment: "Context menu item for sharing a link URL")
            let shareAction = UIAlertAction(title: shareTitle, style: UIAlertActionStyle.Default) { _ in
                self.presentActivityViewController(url, sourceView: self.view, sourceRect: CGRect(origin: touchPoint, size: touchSize), arrowDirection: .Any)
            }
            actionSheetController.addAction(shareAction)
        }

        if let url = elements.image {
            if dialogTitle == nil {
                dialogTitle = url.absoluteString
            }

            let photoAuthorizeStatus = PHPhotoLibrary.authorizationStatus()
            let saveImageTitle = NSLocalizedString("Save Image", comment: "Context menu item for saving an image")
            let saveImageAction = UIAlertAction(title: saveImageTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) -> Void in
                if photoAuthorizeStatus == PHAuthorizationStatus.Authorized || photoAuthorizeStatus == PHAuthorizationStatus.NotDetermined {
                    self.getImage(url) { UIImageWriteToSavedPhotosAlbum($0, nil, nil, nil) }
                } else {
                    let accessDenied = UIAlertController(title: NSLocalizedString("Firefox would like to access your Photos", comment: "See http://mzl.la/1G7uHo7"), message: NSLocalizedString("This allows you to save the image to your Camera Roll.", comment: "See http://mzl.la/1G7uHo7"), preferredStyle: UIAlertControllerStyle.Alert)
                    let dismissAction = UIAlertAction(title: UIConstants.CancelString, style: UIAlertActionStyle.Default, handler: nil)
                    accessDenied.addAction(dismissAction)
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Open Settings", comment: "See http://mzl.la/1G7uHo7"), style: UIAlertActionStyle.Default ) { (action: UIAlertAction!) -> Void in
                        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                    }
                    accessDenied.addAction(settingsAction)
                    self.presentViewController(accessDenied, animated: true, completion: nil)

                }
            }
            actionSheetController.addAction(saveImageAction)

            let copyImageTitle = NSLocalizedString("Copy Image", comment: "Context menu item for copying an image to the clipboard")
            let copyAction = UIAlertAction(title: copyImageTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) -> Void in
                // put the actual image on the clipboard
                // do this asynchronously just in case we're in a low bandwidth situation
                let pasteboard = UIPasteboard.generalPasteboard()
                pasteboard.URL = url
                let changeCount = pasteboard.changeCount
                let application = UIApplication.sharedApplication()
                var taskId: UIBackgroundTaskIdentifier = 0
                taskId = application.beginBackgroundTaskWithExpirationHandler { _ in
                    application.endBackgroundTask(taskId)
                }

                Alamofire.request(.GET, url)
                    .validate(statusCode: 200..<300)
                    .response { responseRequest, responseResponse, responseData, responseError in
                        // Only set the image onto the pasteboard if the pasteboard hasn't changed since
                        // fetching the image; otherwise, in low-bandwidth situations,
                        // we might be overwriting something that the user has subsequently added.
                        if changeCount == pasteboard.changeCount, let imageData = responseData where responseError == nil {
                            pasteboard.addImageWithData(imageData, forURL: url)
                        }

                        application.endBackgroundTask(taskId)
                }
            }
            actionSheetController.addAction(copyAction)
        }

        // If we're showing an arrow popup, set the anchor to the long press location.
        if let popoverPresentationController = actionSheetController.popoverPresentationController {
            popoverPresentationController.sourceView = view
            popoverPresentationController.sourceRect = CGRect(origin: touchPoint, size: touchSize)
            popoverPresentationController.permittedArrowDirections = .Any
        }

        actionSheetController.title = dialogTitle?.ellipsize(maxLength: ActionSheetTitleMaxLength)
        let cancelAction = UIAlertAction(title: UIConstants.CancelString, style: UIAlertActionStyle.Cancel, handler: nil)
        actionSheetController.addAction(cancelAction)
        self.presentViewController(actionSheetController, animated: true, completion: nil)
    }

    private func getImage(url: NSURL, success: UIImage -> ()) {
        Alamofire.request(.GET, url)
            .validate(statusCode: 200..<300)
            .response { _, _, data, _ in
                if let data = data,
                   let image = UIImage.dataIsGIF(data) ? UIImage.imageFromGIFDataThreadSafe(data) : UIImage.imageFromDataThreadSafe(data) {
                    success(image)
                }
            }
    }
}

/**
 A third party search engine Browser extension
**/
extension BrowserViewController {

    func addCustomSearchButtonToWebView(webView: WKWebView) {
        //check if the search engine has already been added.
        let domain = webView.URL?.domainURL().host
        let matches = self.profile.searchEngines.orderedEngines.filter {$0.shortName == domain}
        if !matches.isEmpty {
            self.customSearchEngineButton.tintColor = UIColor.grayColor()
            self.customSearchEngineButton.userInteractionEnabled = false
        } else {
            self.customSearchEngineButton.tintColor = UIConstants.SystemBlueColor
            self.customSearchEngineButton.userInteractionEnabled = true
        }

        /*
         This is how we access hidden views in the WKContentView
         Using the public headers we can find the keyboard accessoryView which is not usually available.
         Specific values here are from the WKContentView headers.
         https://github.com/JaviSoto/iOS9-Runtime-Headers/blob/master/Frameworks/WebKit.framework/WKContentView.h
        */
        guard let webContentView = UIView.findSubViewWithFirstResponder(webView) else {
            /*
             In some cases the URL bar can trigger the keyboard notification. In that case the webview isnt the first responder
             and a search button should not be added.
             */
            return
        }

        guard let input = webContentView.performSelector(Selector("inputAccessoryView")),
            let inputView = input.takeUnretainedValue() as? UIInputView,
            let nextButton = inputView.valueForKey("_nextItem") as? UIBarButtonItem,
            let nextButtonView = nextButton.valueForKey("view") as? UIView else {
                //failed to find the inputView instead lets use the inputAssistant
                addCustomSearchButtonToInputAssistant(webContentView)
                return
            }
            inputView.addSubview(self.customSearchEngineButton)
            self.customSearchEngineButton.snp_remakeConstraints { make in
                make.leading.equalTo(nextButtonView.snp_trailing).offset(20)
                make.width.equalTo(inputView.snp_height)
                make.top.equalTo(nextButtonView.snp_top)
                make.height.equalTo(inputView.snp_height)
            }
    }

    /**
     This adds the customSearchButton to the inputAssistant
     for cases where the inputAccessoryView could not be found for example
     on the iPad where it does not exist. However this only works on iOS9
     **/
    func addCustomSearchButtonToInputAssistant(webContentView: UIView) {
        guard customSearchBarButton == nil else {
            return //The searchButton is already on the keyboard
        }
        let inputAssistant = webContentView.inputAssistantItem
        let item = UIBarButtonItem(customView: customSearchEngineButton)
        customSearchBarButton = item
        inputAssistant.trailingBarButtonGroups.last?.barButtonItems.append(item)
    }

    func addCustomSearchEngineForFocusedElement() {
        guard let webView = tabManager.selectedTab?.webView else {
            return
        }
        webView.evaluateJavaScript("__firefox__.searchQueryForField()") { (result, _) in
            guard let searchQuery = result as? String, favicon = self.tabManager.selectedTab!.displayFavicon else {
                //Javascript responded with an incorrectly formatted message. Show an error.
                let alert = ThirdPartySearchAlerts.failedToAddThirdPartySearch()
                self.presentViewController(alert, animated: true, completion: nil)
                return
            }
            self.addSearchEngine(searchQuery, favicon: favicon)
            self.customSearchEngineButton.tintColor = UIColor.grayColor()
            self.customSearchEngineButton.userInteractionEnabled = false
        }
    }

    func addSearchEngine(searchQuery: String, favicon: Favicon) {
        guard searchQuery != "",
            let iconURL = NSURL(string: favicon.url),
            let url = NSURL(string: searchQuery.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLFragmentAllowedCharacterSet())!),
            let shortName = url.domainURL().host else {
                let alert = ThirdPartySearchAlerts.failedToAddThirdPartySearch()
                self.presentViewController(alert, animated: true, completion: nil)
                return
        }

        let alert = ThirdPartySearchAlerts.addThirdPartySearchEngine { alert in
            self.customSearchEngineButton.tintColor = UIColor.grayColor()
            self.customSearchEngineButton.userInteractionEnabled = false
            SDWebImageManager.sharedManager().downloadImageWithURL(iconURL, options: SDWebImageOptions.ContinueInBackground, progress: nil) { (image, error, cacheType, success, url) in
                guard image != nil else {
                    let alert = ThirdPartySearchAlerts.failedToAddThirdPartySearch()
                    self.presentViewController(alert, animated: true, completion: nil)
                    return
                }

                self.profile.searchEngines.addSearchEngine(OpenSearchEngine(engineID: nil, shortName: shortName, image: image, searchTemplate: searchQuery, suggestTemplate: nil, isCustomEngine: true))
                let Toast = SimpleToast()
                Toast.showAlertWithText(Strings.ThirdPartySearchEngineAdded)
            }
        }

        self.presentViewController(alert, animated: true, completion: {})
    }
}

extension BrowserViewController: KeyboardHelperDelegate {
    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        keyboardState = state
        updateViewConstraints()

        UIView.animateWithDuration(state.animationDuration) {
            UIView.setAnimationCurve(state.animationCurve)
            self.findInPageContainer.layoutIfNeeded()
            self.snackBars.layoutIfNeeded()
        }

        if let webView = tabManager.selectedTab?.webView {
            webView.evaluateJavaScript("__firefox__.searchQueryForField()") { (result, _) in
                guard let _ = result as? String else {
                    return
                }
                self.addCustomSearchButtonToWebView(webView)
            }
        }
    }

    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState) {
    }

    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        keyboardState = nil
        updateViewConstraints()
        //If the searchEngineButton exists remove it form the keyboard
        if let buttonGroup = customSearchBarButton?.buttonGroup {
            buttonGroup.barButtonItems = buttonGroup.barButtonItems.filter { $0 != customSearchBarButton }
            customSearchBarButton = nil
        }

        if self.customSearchEngineButton.superview != nil {
            self.customSearchEngineButton.removeFromSuperview()
        }

        UIView.animateWithDuration(state.animationDuration) {
            UIView.setAnimationCurve(state.animationCurve)
            self.findInPageContainer.layoutIfNeeded()
            self.snackBars.layoutIfNeeded()
        }
    }
}

extension BrowserViewController: SessionRestoreHelperDelegate {
    func sessionRestoreHelper(helper: SessionRestoreHelper, didRestoreSessionForTab tab: Tab) {
        tab.restoring = false

        if let tab = tabManager.selectedTab where tab.webView === tab.webView {
            updateUIForReaderHomeStateForTab(tab)
        }
    }
}

extension BrowserViewController: TabTrayDelegate {
    // This function animates and resets the tab chrome transforms when
    // the tab tray dismisses.
    func tabTrayDidDismiss(tabTray: TabTrayController) {
        resetBrowserChrome()
    }

    func tabTrayDidAddBookmark(tab: Tab) {
        guard let url = tab.url?.absoluteString where url.characters.count > 0 else { return }
        self.addBookmark(tab.tabState)
    }


    func tabTrayDidAddToReadingList(tab: Tab) -> ReadingListClientRecord? {
        guard let url = tab.url?.absoluteString where url.characters.count > 0 else { return nil }
        return profile.readingList?.createRecordWithURL(url, title: tab.title ?? url, addedBy: UIDevice.currentDevice().name).successValue
    }

    func tabTrayRequestsPresentationOf(viewController viewController: UIViewController) {
        self.presentViewController(viewController, animated: false, completion: nil)
    }
}

// MARK: Browser Chrome Theming
extension BrowserViewController: Themeable {

    func applyTheme(themeName: String) {
        urlBar.applyTheme(themeName)
        toolbar?.applyTheme(themeName)
        readerModeBar?.applyTheme(themeName)
        topTabsViewController?.applyTheme(themeName)

        switch(themeName) {
        case Theme.NormalMode:
            header.blurStyle = .ExtraLight
            footerBackground?.blurStyle = .ExtraLight
        case Theme.PrivateMode:
            header.blurStyle = .Dark
            footerBackground?.blurStyle = .Dark
        default:
            log.debug("Unknown Theme \(themeName)")
        }
    }
}

// A small convienent class for wrapping a view with a blur background that can be modified
class BlurWrapper: UIView {
    var blurStyle: UIBlurEffectStyle = .ExtraLight {
        didSet {
            let newEffect = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
            effectView.removeFromSuperview()
            effectView = newEffect
            insertSubview(effectView, belowSubview: wrappedView)
            effectView.snp_remakeConstraints { make in
                make.edges.equalTo(self)
            }
            effectView.hidden = disableBlur
            switch blurStyle {
            case .ExtraLight, .Light:
                background.backgroundColor = TopTabsUX.TopTabsBackgroundNormalColor
            case .ExtraDark, .Dark:
                background.backgroundColor = TopTabsUX.TopTabsBackgroundPrivateColor
            default:
                assertionFailure("Unsupported blur style")
            }
        }
    }
    
    var disableBlur = false {
        didSet {
            effectView.hidden = disableBlur
            background.hidden = !disableBlur
        }
    }
    

    private var effectView: UIVisualEffectView
    private var wrappedView: UIView
    private lazy var background: UIView = {
        let background = UIView()
        background.hidden = true
        return background
    }()

    init(view: UIView) {
        wrappedView = view
        effectView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        super.init(frame: CGRectZero)

        addSubview(background)
        addSubview(effectView)
        addSubview(wrappedView)

        effectView.snp_makeConstraints { make in
            make.edges.equalTo(self)
        }

        wrappedView.snp_makeConstraints { make in
            make.edges.equalTo(self)
        }
        
        background.snp_makeConstraints { make in
            make.edges.equalTo(self)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

protocol Themeable {
    func applyTheme(themeName: String)
}

extension BrowserViewController: FindInPageBarDelegate, FindInPageHelperDelegate {
    func findInPage(findInPage: FindInPageBar, didTextChange text: String) {
        find(text, function: "find")
    }

    func findInPage(findInPage: FindInPageBar, didFindNextWithText text: String) {
        findInPageBar?.endEditing(true)
        find(text, function: "findNext")
    }

    func findInPage(findInPage: FindInPageBar, didFindPreviousWithText text: String) {
        findInPageBar?.endEditing(true)
        find(text, function: "findPrevious")
    }

    func findInPageDidPressClose(findInPage: FindInPageBar) {
        updateFindInPageVisibility(visible: false)
    }

    private func find(text: String, function: String) {
        guard let webView = tabManager.selectedTab?.webView else { return }

        let escaped = text.stringByReplacingOccurrencesOfString("\\", withString: "\\\\")
                          .stringByReplacingOccurrencesOfString("\"", withString: "\\\"")

        webView.evaluateJavaScript("__firefox__.\(function)(\"\(escaped)\")", completionHandler: nil)
    }

    func findInPageHelper(findInPageHelper: FindInPageHelper, didUpdateCurrentResult currentResult: Int) {
        findInPageBar?.currentResult = currentResult
    }

    func findInPageHelper(findInPageHelper: FindInPageHelper, didUpdateTotalResults totalResults: Int) {
        findInPageBar?.totalResults = totalResults
    }
}

extension BrowserViewController: JSPromptAlertControllerDelegate {
    func promptAlertControllerDidDismiss(alertController: JSPromptAlertController) {
        showQueuedAlertIfAvailable()
    }
}

private extension WKNavigationAction {
    /// Allow local requests only if the request is privileged.
    private var isAllowed: Bool {
        guard let url = request.URL else {
            return true
        }

        return !url.isWebPage(includeDataURIs: false) || !url.isLocal || request.isPrivileged
    }
}

extension BrowserViewController: TopTabsDelegate {
    func topTabsDidPressTabs() {
        urlBar.leaveOverlayMode(didCancel: true)
        self.urlBarDidPressTabs(urlBar)
    }
    
    func topTabsDidPressNewTab() {
        let isPrivate = tabManager.selectedTab?.isPrivate ?? false
        openBlankNewTabAndFocus(isPrivate: isPrivate)
    }

    func topTabsDidPressPrivateModeButton(cachedTab: Tab?) {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }
        urlBar.leaveOverlayMode()
        
        if selectedTab.isPrivate {
            if profile.prefs.boolForKey("settings.closePrivateTabs") ?? false {
                tabManager.removeAllPrivateTabsAndNotify(false)
            }
        }
        
        if let tab = cachedTab {
            tabManager.selectTab(tab)
        } else if selectedTab.isPrivate {
            tabManager.selectTab(tabManager.normalTabs.last)
        } else {
            if let privateTab = tabManager.privateTabs.last {
                tabManager.selectTab(privateTab)
            } else {
                openBlankNewTabAndFocus(isPrivate: true)
            }
        }
    }
    
    func topTabsDidChangeTab() {
        urlBar.leaveOverlayMode(didCancel: true)
    }
}

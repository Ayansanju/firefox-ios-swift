// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit

class TabToolbar: UIView {
    weak var tabToolbarDelegate: TabToolbarDelegate?

    let tabsButton = TabsButton()
    let addNewTabButton = ToolbarButton()
    let appMenuButton = ToolbarButton()
    let bookmarksButton = ToolbarButton()
    let forwardButton = ToolbarButton()
    let backButton = ToolbarButton()
    let multiStateButton = ToolbarButton()
    let actionButtons: [NotificationThemeable & UIButton]

    fileprivate let privateModeBadge = BadgeWithBackdrop(imageName: "privateModeBadge", backdropCircleColor: UIColor.Defaults.MobilePrivatePurple)
    fileprivate let appMenuBadge = BadgeWithBackdrop(imageName: "menuBadge")
    fileprivate let warningMenuBadge = BadgeWithBackdrop(imageName: "menuWarning", imageMask: "warning-mask")

    var helper: TabToolbarHelper?
    private let contentView = UIStackView()
    private var isBottomSearchBar: Bool {
        return BrowserViewController.foregroundBVC().isBottomSearchBar
    }

    fileprivate override init(frame: CGRect) {
        actionButtons = [backButton, forwardButton, multiStateButton, addNewTabButton, tabsButton, appMenuButton]
        super.init(frame: frame)
        setupAccessibility()

        addSubview(contentView)
        helper = TabToolbarHelper(toolbar: self)
        addButtons(actionButtons)

        privateModeBadge.add(toParent: contentView)
        appMenuBadge.add(toParent: contentView)
        warningMenuBadge.add(toParent: contentView)

        contentView.axis = .horizontal
        contentView.distribution = .fillEqually
    }

    override func updateConstraints() {
        privateModeBadge.layout(onButton: tabsButton)
        appMenuBadge.layout(onButton: appMenuButton)
        warningMenuBadge.layout(onButton: appMenuButton)

        contentView.snp.makeConstraints { make in
            make.leading.trailing.top.equalTo(self)
            make.bottom.equalTo(self.safeArea.bottom)
        }
        super.updateConstraints()
    }

    private func setupAccessibility() {
        backButton.accessibilityIdentifier = "TabToolbar.backButton"
        forwardButton.accessibilityIdentifier = "TabToolbar.forwardButton"
        multiStateButton.accessibilityIdentifier = "TabToolbar.multiStateButton"
        tabsButton.accessibilityIdentifier = "TabToolbar.tabsButton"
        addNewTabButton.accessibilityIdentifier = "TabToolbar.addNewTabButton"
        appMenuButton.accessibilityIdentifier = AccessibilityIdentifiers.BottomToolbar.settingsMenuButton
        accessibilityNavigationStyle = .combined
        accessibilityLabel = .TabToolbarNavigationToolbarAccessibilityLabel
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addButtons(_ buttons: [UIButton]) {
        buttons.forEach { contentView.addArrangedSubview($0) }
    }

    override func draw(_ rect: CGRect) {
        // No line when the search bar is on top of the toolbar
        guard !isBottomSearchBar else { return }
        if let context = UIGraphicsGetCurrentContext() {
            drawLine(context, start: .zero, end: CGPoint(x: frame.width, y: 0))
        }
    }

    fileprivate func drawLine(_ context: CGContext, start: CGPoint, end: CGPoint) {
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.05).cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: start.x, y: start.y))
        context.addLine(to: CGPoint(x: end.x, y: end.y))
        context.strokePath()
    }
}

extension TabToolbar: TabToolbarProtocol {
    var homeButton: ToolbarButton { multiStateButton }

    func privateModeBadge(visible: Bool) {
        privateModeBadge.show(visible)
    }

    func warningMenuBadge(setVisible: Bool) {
        // Disable other menu badges before showing the warning.
        if !appMenuBadge.badge.isHidden { appMenuBadge.show(false) }
        warningMenuBadge.show(setVisible)
    }

    func updateBackStatus(_ canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func updateForwardStatus(_ canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    func updateMiddleButtonState(_ state: MiddleButtonState) {
        helper?.setMiddleButtonState(state)
    }

    func updatePageStatus(_ isWebPage: Bool) {

    }

    func updateTabCount(_ count: Int, animated: Bool) {
        tabsButton.updateTabCount(count, animated: animated)
    }
}

extension TabToolbar: NotificationThemeable, PrivateModeUI {
    func applyTheme() {
        backgroundColor = UIColor.theme.browser.background
        helper?.setTheme(forButtons: actionButtons)

        privateModeBadge.badge.tintBackground(color: UIColor.theme.browser.background)
        appMenuBadge.badge.tintBackground(color: UIColor.theme.browser.background)
        warningMenuBadge.badge.tintBackground(color: UIColor.theme.browser.background)
    }

    func applyUIMode(isPrivate: Bool) {
        privateModeBadge(visible: isPrivate)
    }
}

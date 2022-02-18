// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Storage
import Shared
import UIKit

// This file is main table view used for the action sheet
class PhotonActionSheet: UIViewController, UIGestureRecognizerDelegate, NotificationThemeable {

    // MARK: - Variables
    private var tableView = UITableView(frame: .zero, style: .grouped)
    private var viewModel: PhotonActionSheetViewModel!
    private var constraints = [NSLayoutConstraint]()

    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let tapRecognizer = UITapGestureRecognizer()
        tapRecognizer.addTarget(self, action: #selector(dismiss))
        tapRecognizer.numberOfTapsRequired = 1
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = self
        return tapRecognizer
    }()

    private lazy var closeButton: UIButton = .build { button in
        button.setTitle(.CloseButtonTitle, for: .normal)
        button.setTitleColor(UIConstants.SystemBlueColor, for: .normal)
        button.layer.cornerRadius = PhotonActionSheetUX.CornerRadius
        button.titleLabel?.font = DynamicFontHelper.defaultHelper.DeviceFontExtraLargeBold
        button.addTarget(self, action: #selector(self.dismiss), for: .touchUpInside)
        button.accessibilityIdentifier = "PhotonMenu.close"
    }

    var photonTransitionDelegate: UIViewControllerTransitioningDelegate? {
        didSet {
            transitioningDelegate = photonTransitionDelegate
        }
    }

    // MARK: - Init

    init(viewModel: PhotonActionSheetViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        title = viewModel.title
        modalPresentationStyle = viewModel.modalStyle
        closeButton.setTitle(viewModel.closeButtonTitle, for: .normal)
        tableView.estimatedRowHeight = PhotonActionSheetUX.RowHeight
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        tableView.dataSource = nil
        tableView.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - View cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addGestureRecognizer(tapRecognizer)
        view.addSubview(tableView)
        view.accessibilityIdentifier = "Action Sheet"

        tableView.backgroundColor = .clear
        tableView.addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
        // In a popover the popover provides the blur background
        // Not using a background color allows the view to style correctly with the popover arrow
        if self.popoverPresentationController == nil {
            let blurEffect = UIBlurEffect(style: UIColor.theme.actionMenu.iPhoneBackgroundBlurStyle)
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            tableView.backgroundView = blurEffectView
        }

        if viewModel.presentationStyle == .bottom {
            setupBottomStyle()
        } else if viewModel.presentationStyle == .popover {
            setupPopoverStyle()
        } else {
            setupCenteredStyle()
        }

        tableViewHeightConstraint = tableView.heightAnchor.constraint(equalToConstant: 0)
        tableViewHeightConstraint?.isActive = true
        NSLayoutConstraint.activate(constraints)

        NotificationCenter.default.addObserver(self, selector: #selector(stopRotateSyncIcon),
                                               name: .ProfileDidFinishSyncing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopRotateSyncIcon),
                                               name: .ProfileDidStartSyncing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reduceTransparencyChanged),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        tableView.removeObserver(self, forKeyPath: "contentSize")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        applyTheme()

        tableView.bounces = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(PhotonActionSheetContainerCell.self, forCellReuseIdentifier: PhotonActionSheetUX.CellName)
        tableView.register(PhotonActionSheetSiteHeaderView.self, forHeaderFooterViewReuseIdentifier: PhotonActionSheetUX.SiteHeaderName)
        tableView.register(PhotonActionSheetTitleHeaderView.self, forHeaderFooterViewReuseIdentifier: PhotonActionSheetUX.TitleHeaderName)
        tableView.register(PhotonActionSheetSeparator.self, forHeaderFooterViewReuseIdentifier: "SeparatorSectionHeader")
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "EmptyHeader")

        tableView.isScrollEnabled = true
        tableView.showsVerticalScrollIndicator = false
        tableView.layer.cornerRadius = PhotonActionSheetUX.CornerRadius
        // Don't show separators on ETP menu
        if viewModel.title != nil {
            tableView.separatorStyle = .none
        }
        tableView.separatorColor = UIColor.clear
        tableView.separatorInset = .zero
        tableView.cellLayoutMarginsFollowReadableWidth = false
        tableView.accessibilityIdentifier = "Context Menu"
        tableView.translatesAutoresizingMaskIntoConstraints = false

        if viewModel.toolbarMenuInversed {
            tableView.transform = CGAffineTransform(scaleX: 1, y: -1)
        }
        tableView.reloadData()

        DispatchQueue.main.async {
            // Pick up the correct/final tableview.contentsize in order to set the height.
            // Without async dispatch, the contentsize is wrong.
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        setTableViewHeight()
    }

    private var tableViewHeightConstraint: NSLayoutConstraint?
    private func setTableViewHeight() {
        var frameHeight: CGFloat
        frameHeight = view.safeAreaLayoutGuide.layoutFrame.size.height
        let buttonHeight = viewModel.presentationStyle == .bottom ? PhotonActionSheetUX.CloseButtonHeight : 0
        let maxHeight = frameHeight - buttonHeight

        // The height of the menu should be no more than 90 percent of the screen
        let height = min(tableView.contentSize.height, maxHeight * 0.90)
        tableViewHeightConstraint?.constant = height
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass
            || traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass {
            updateViewConstraints()
        }
    }

    // MARK: - Setup

    private func setupBottomStyle() {
        self.view.addSubview(closeButton)

        let bottomConstraints = [
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: centeredAndBottomWidth),
            closeButton.heightAnchor.constraint(equalToConstant: PhotonActionSheetUX.CloseButtonHeight),
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -PhotonActionSheetUX.Padding),

            tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -PhotonActionSheetUX.Padding),
            tableView.widthAnchor.constraint(equalToConstant: centeredAndBottomWidth),
        ]
        constraints.append(contentsOf: bottomConstraints)
    }

    private func setupPopoverStyle() {
        let width: CGFloat = viewModel.popOverWidthForTraitCollection(trait: view.traitCollection)

        let tableViewConstraints = [
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.widthAnchor.constraint(greaterThanOrEqualToConstant: width),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        constraints.append(contentsOf: tableViewConstraints)
    }

    private func setupCenteredStyle() {
        let tableViewConstraints = [
            tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            tableView.widthAnchor.constraint(equalToConstant: centeredAndBottomWidth),
        ]
        constraints.append(contentsOf: tableViewConstraints)

        applyBackgroundBlur()
        viewModel.tintColor = UIConstants.SystemBlueColor
    }

    // The width used for the .centered and .bottom style
    private var centeredAndBottomWidth: CGFloat {
        let minimumWidth = min(view.frame.size.width, PhotonActionSheetUX.MaxWidth)
        return minimumWidth - (PhotonActionSheetUX.Padding * 2)
    }

    // MARK: - Theme

    @objc func reduceTransparencyChanged() {
        // If the user toggles transparency settings, re-apply the theme to also toggle the blur effect.
        applyTheme()
    }

    func applyTheme() {
        if viewModel.presentationStyle == .popover {
            view.backgroundColor = UIColor.theme.browser.background.withAlphaComponent(0.7)
        } else {
            tableView.backgroundView?.backgroundColor = UIColor.theme.actionMenu.iPhoneBackground
        }

        // Apply or remove the background blur effect
        if let visualEffectView = tableView.backgroundView as? UIVisualEffectView {
            if UIAccessibility.isReduceTransparencyEnabled {
                // Remove the visual effect and the background alpha
                visualEffectView.effect = nil
                tableView.backgroundView?.backgroundColor = UIColor.theme.actionMenu.iPhoneBackground.withAlphaComponent(1.0)
            } else {
                visualEffectView.effect = UIBlurEffect(style: UIColor.theme.actionMenu.iPhoneBackgroundBlurStyle)
            }
        }

        viewModel.tintColor = UIColor.theme.actionMenu.foreground
        closeButton.backgroundColor = UIColor.theme.actionMenu.closeButtonBackground
        tableView.headerView(forSection: 0)?.backgroundColor = UIColor.Photon.DarkGrey05
    }

    private func applyBackgroundBlur() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        guard let screenshot = appDelegate.window?.screenshot() else { return }

        let blurredImage = screenshot.applyBlur(withRadius: 5,
                                                blurType: BOXFILTER,
                                                tintColor: UIColor.black.withAlphaComponent(0.2),
                                                saturationDeltaFactor: 1.8,
                                                maskImage: nil)
        let imageView = UIImageView(image: blurredImage)
        view.insertSubview(imageView, belowSubview: tableView)
    }

    // MARK: - Actions

    @objc private func dismiss(_ gestureRecognizer: UIGestureRecognizer?) {
        dismiss(animated: true, completion: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return !tableView.frame.contains(touch.location(in: view))
    }

    @objc private func stopRotateSyncIcon() {
        ensureMainThread {
            self.tableView.reloadData()
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if viewModel.presentationStyle == .popover {
            preferredContentSize = tableView.contentSize
        }
    }
}

// MARK: - UITableViewDelegate
extension PhotonActionSheet: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let action = viewModel.actions[indexPath.section][indexPath.row]
        // TODO: Laurie Click action

//        guard let handler = action.tapHandler else {
//            self.dismiss(nil)
//            return
//        }
//
//        // Switches can be toggled on/off without dismissing the menu
//        if action.accessory == .Switch {
//            let generator = UIImpactFeedbackGenerator(style: .medium)
//            generator.impactOccurred()
//            action.isEnabled = !action.isEnabled
//            viewModel.actions[indexPath.section][indexPath.row] = action
//            self.tableView.deselectRow(at: indexPath, animated: true)
//            self.tableView.reloadData()
//        } else {
//            action.isEnabled = !action.isEnabled
//            self.dismiss(nil)
//        }
//
//        return handler(action, self.tableView(tableView, cellForRowAt: indexPath))
    }
}

// MARK: - UITableViewDataSource
extension PhotonActionSheet: UITableViewDataSource {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // TODO: Laurie - handle in child
        guard let section = viewModel.actions[safe: indexPath.section],
              let action = section[safe: indexPath.row],
              let custom = action.items[0].customHeight else { return UITableView.automaticDimension }

        // Nested tableview rows get additional height
        return custom(action.items[0])
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.actions.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.actions[section].count
    }

    func tableView(_ tableView: UITableView, hasFullWidthSeparatorForRowAtIndexPath indexPath: IndexPath) -> Bool {
        return false
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PhotonActionSheetUX.CellName, for: indexPath) as! PhotonActionSheetContainerCell
        let actions = viewModel.actions[indexPath.section][indexPath.row]
        cell.configure(at: indexPath, actions: actions, viewModel: viewModel)

        if viewModel.toolbarMenuInversed {
            let rowIsLastInSection = indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
            cell.hideBottomBorder(isHidden: rowIsLastInSection)

        } else if viewModel.modalStyle == .popover {
            let isLastRow = indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
            let isLastSection = indexPath.section == tableView.numberOfSections - 1
            let rowIsLast = isLastRow && isLastSection
            cell.hideBottomBorder(isHidden: rowIsLast)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return viewModel.getHeaderHeightForSection(section: section)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return viewModel.getViewHeader(tableView: tableView, section: section)
    }
}

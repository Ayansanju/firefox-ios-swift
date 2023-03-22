// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common
import Shared

protocol ZoomPageBarDelegate: AnyObject {
    func zoomPageDidPressClose()
}

class ZoomPageBar: UIView {
    private struct UX {
        static let leadingTrailingPadding: CGFloat = 10
        static let topBottomPadding: CGFloat = 18
        static let stepperWidth: CGFloat = 222
        static let stepperHeight: CGFloat = 36
        static let stepperTopBottomPadding: CGFloat = 10
        static let stepperCornerRadius: CGFloat = 8
        static let stepperShadowRadius: CGFloat = 4
        static let stepperSpacing: CGFloat = 10
        static let stepperShadowOpacity: Float = 1
        static let stepperShadowOffset = CGSize(width: 0, height: 4)
        static let separatorWidth: CGFloat = 1
        static let separatorHeightMultiplier = 0.75
        static let fontSize: CGFloat = 16
        static let lowerZoomLimit: CGFloat = 0.5
        static let upperZoomLimit: CGFloat = 2.0
        static let zoomInButtonInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 18)
        static let zoomOutButtonInsets = UIEdgeInsets(top: 6, left: 18, bottom: 6, right: 8)
    }

    weak var delegate: ZoomPageBarDelegate?
    private let gestureRecognizer = UITapGestureRecognizer()
    private var stepperLeadingConstraint = NSLayoutConstraint()
    private var stepperCenterXConstraint = NSLayoutConstraint()

    private let tab: Tab
    private let isIpad: Bool

    private let leftSeparator: UIView = .build()
    private let rightSeparator: UIView = .build()

    private let stepperContainer: UIStackView = .build { view in
        view.axis = .horizontal
        view.alignment = .center
        view.distribution = .fill
        view.spacing = UX.stepperSpacing
        view.layer.cornerRadius = UX.stepperCornerRadius
        view.layer.shadowRadius = UX.stepperShadowRadius
        view.layer.shadowOffset = UX.stepperShadowOffset
        view.layer.shadowOpacity = UX.stepperShadowOpacity
        view.clipsToBounds = false
    }

    private let zoomOutButton: UIButton = .build { button in
        button.setImage(UIImage.templateImageNamed(ImageIdentifiers.subtract), for: [])
        button.accessibilityIdentifier = AccessibilityIdentifiers.ZoomPageBar.zoomPageZoomOutButton
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.contentEdgeInsets = UX.zoomOutButtonInsets
    }

    private let zoomInButton: UIButton = .build { button in
        button.setImage(UIImage.templateImageNamed(ImageIdentifiers.add), for: [])
        button.accessibilityIdentifier = AccessibilityIdentifiers.ZoomPageBar.zoomPageZoomInButton
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.contentEdgeInsets = UX.zoomInButtonInsets
    }

    private let zoomLevel: UILabel = .build { label in
        label.font = DynamicFontHelper.defaultHelper.preferredBoldFont(withTextStyle: .callout,
                                                                       size: UX.fontSize)
        label.isUserInteractionEnabled = true
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
    }

    private let closeButton: UIButton = .build { button in
        button.setImage(UIImage.templateImageNamed(ImageIdentifiers.xMark), for: [])
        button.accessibilityLabel = .FindInPageDoneAccessibilityLabel
        button.accessibilityIdentifier = AccessibilityIdentifiers.FindInPage.findInPageCloseButton
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    init(tab: Tab, isIpad: Bool) {
        self.tab = tab
        self.isIpad = isIpad

        super.init(frame: .zero)

        setupViews()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateStepperConstraintsBasedOnSizeClass()
    }

    private func setupViews() {
        zoomInButton.addTarget(self, action: #selector(didPressZoomIn), for: .touchUpInside)
        zoomOutButton.addTarget(self, action: #selector(didPressZoomOut), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(didPressClose), for: .touchUpInside)

        gestureRecognizer.addTarget(self, action: #selector(didPressReset))
        zoomLevel.addGestureRecognizer(gestureRecognizer)

        updateZoomLabel()
        checkPageZoomLimits()

        [zoomOutButton, leftSeparator, zoomLevel, rightSeparator, zoomInButton].forEach {
            stepperContainer.addArrangedSubview($0)
        }

        addSubviews(stepperContainer, closeButton)
    }

    private func setupLayout() {
        stepperCenterXConstraint = stepperContainer.centerXAnchor.constraint(equalTo: centerXAnchor)
        stepperLeadingConstraint = stepperContainer.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                                             constant: UX.leadingTrailingPadding)
        setupSeparator(leftSeparator)
        setupSeparator(rightSeparator)

        NSLayoutConstraint.activate([
            stepperContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor,
                                                  constant: UX.stepperTopBottomPadding),
            stepperContainer.bottomAnchor.constraint(greaterThanOrEqualTo: bottomAnchor,
                                                     constant: UX.stepperTopBottomPadding),
            stepperContainer.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor),
            stepperContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: UX.stepperHeight),
            stepperContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: UX.stepperWidth),
            stepperContainer.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                  constant: -UX.leadingTrailingPadding),
        ])
    }

    private func setupSeparator(_ separator: UIView) {
        separator.widthAnchor.constraint(equalToConstant: UX.separatorWidth).isActive = true
        separator.heightAnchor.constraint(equalTo: stepperContainer.heightAnchor,
                                          multiplier: UX.separatorHeightMultiplier).isActive = true
    }

    private func updateZoomLabel() {
        zoomLevel.text = String(format: "%.0f%%", tab.pageZoom * 100.0)
        zoomLevel.isEnabled = tab.pageZoom == 1.0 ? false : true
        gestureRecognizer.isEnabled = !(tab.pageZoom == 1.0)
    }

    private func enableZoomButtons() {
        zoomInButton.isEnabled = true
        zoomOutButton.isEnabled = true
    }

    private func checkPageZoomLimits() {
        if tab.pageZoom <= UX.lowerZoomLimit {
            zoomOutButton.isEnabled = false
        } else if tab.pageZoom >= UX.upperZoomLimit {
            zoomInButton.isEnabled = false
        }
    }

    private func updateStepperConstraintsBasedOnSizeClass() {
        if traitCollection.horizontalSizeClass == .regular &&
            traitCollection.verticalSizeClass == .regular ||
            traitCollection.horizontalSizeClass == .compact &&
            traitCollection.verticalSizeClass == .compact {
            stepperLeadingConstraint.isActive = false
            stepperCenterXConstraint.isActive = true
        } else {
            stepperCenterXConstraint.isActive = false
            stepperLeadingConstraint.isActive = true
        }
    }

    @objc private func didPressZoomIn(_ sender: UIButton) {
        tab.zoomIn()
        updateZoomLabel()

        zoomOutButton.isEnabled = true
        if tab.pageZoom >= UX.upperZoomLimit {
            zoomInButton.isEnabled = false
        }
    }

    @objc private func didPressZoomOut(_ sender: UIButton) {
        tab.zoomOut()
        updateZoomLabel()

        zoomInButton.isEnabled = true
        if tab.pageZoom <= UX.lowerZoomLimit {
            zoomOutButton.isEnabled = false
        }
    }

    @objc private func didPressReset(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            tab.resetZoom()
            updateZoomLabel()
            enableZoomButtons()
        }
    }

    @objc private func didPressClose(_ sender: UIButton) {
        delegate?.zoomPageDidPressClose()
    }
}

extension ZoomPageBar: ThemeApplicable {
    func applyTheme(theme: Theme) {
        backgroundColor = theme.colors.layer1
        stepperContainer.backgroundColor = theme.colors.layer5
        stepperContainer.layer.shadowColor = theme.colors.shadowDefault.cgColor

        leftSeparator.backgroundColor = theme.colors.borderPrimary
        rightSeparator.backgroundColor = theme.colors.borderPrimary

        zoomLevel.tintColor = theme.colors.textPrimary

        zoomInButton.tintColor = theme.colors.iconPrimary
        zoomOutButton.tintColor = theme.colors.iconPrimary
        closeButton.tintColor = theme.colors.iconPrimary
    }
}

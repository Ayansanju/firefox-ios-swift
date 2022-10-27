// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Shared

// MARK: - PocketStandardCell
/// A cell used in FxHomeScreen's Pocket section
class PocketStandardCell: UICollectionViewCell, ReusableCell {

    struct UX {
        static let cellHeight: CGFloat = 112
        static let cellWidth: CGFloat = 350
        static let interItemSpacing = NSCollectionLayoutSpacing.fixed(8)
        static let interGroupSpacing: CGFloat = 8
        static let generalCornerRadius: CGFloat = 12
        static let titleFontSize: CGFloat = 12
        static let sponsoredFontSize: CGFloat = 12
        static let siteFontSize: CGFloat = 12
        static let horizontalMargin: CGFloat = 16
        static let heroImageSize =  CGSize(width: 108, height: 80)
        static let sponsoredIconSize = CGSize(width: 12, height: 12)
        static let sponsoredStackSpacing: CGFloat = 4
    }

    // MARK: - UI Elements
    private lazy var heroImageView: UIImageView = .build { image in
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.masksToBounds = true
        image.layer.cornerRadius = UX.generalCornerRadius
        image.backgroundColor = .clear
    }

    private lazy var titleLabel: UILabel = .build { title in
        title.adjustsFontForContentSizeCategory = true
        title.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .headline,
                                                                   size: UX.titleFontSize)
        title.numberOfLines = 2
    }

    private lazy var bottomTextStackView: UIStackView = .build { stackView in
        stackView.axis = .vertical
        stackView.spacing = UX.sponsoredStackSpacing
        stackView.alignment = .fill
        stackView.distribution = .fill
    }

    private lazy var sponsoredStack: UIStackView = .build { stackView in
        stackView.axis = .horizontal
        stackView.spacing = UX.sponsoredStackSpacing
        stackView.alignment = .center
        stackView.distribution = .fill
    }

    private lazy var sponsoredLabel: UILabel = .build { label in
        label.adjustsFontForContentSizeCategory = true
        label.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .caption2,
                                                                   size: UX.sponsoredFontSize)
        label.text = .FirefoxHomepage.Pocket.Sponsored
    }

    private lazy var sponsoredIcon: UIImageView = .build { image in
        image.image = UIImage(named: ImageIdentifiers.sponsoredStar)
    }

    private lazy var descriptionLabel: UILabel = .build { label in
        label.adjustsFontForContentSizeCategory = true
        label.font = DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .caption1,
                                                                   size: UX.siteFontSize)
    }

    // MARK: - Variables
    private var sponsoredImageCenterConstraint: NSLayoutConstraint?
    private var sponsoredImageFirstBaselineConstraint: NSLayoutConstraint?

    // MARK: - Inits

    override init(frame: CGRect) {
        super.init(frame: .zero)

        isAccessibilityElement = true
        accessibilityIdentifier = AccessibilityIdentifiers.FirefoxHomepage.Pocket.itemCell

        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        heroImageView.image = nil
        descriptionLabel.text = nil
        titleLabel.text = nil
    }

    // MARK: - Helpers

    func configure(viewModel: PocketStandardCellViewModel, theme: Theme) {
        titleLabel.text = viewModel.title
        descriptionLabel.text = viewModel.description
        accessibilityLabel = viewModel.accessibilityLabel
        tag = viewModel.tag

        ImageLoadingHandler.shared.getImageFromCacheOrDownload(
            with: viewModel.imageURL,
            limit: ImageLoadingConstants.NoLimitImageSize
        ) { [weak self] image, error in
            guard error == nil, let image = image, self?.tag == viewModel.tag else { return }
            self?.heroImageView.image = image
        }

        sponsoredStack.isHidden = viewModel.shouldHideSponsor
        descriptionLabel.font = viewModel.shouldHideSponsor
        ? DynamicFontHelper.defaultHelper.preferredFont(withTextStyle: .caption1,
                                                        size: UX.siteFontSize)
        : DynamicFontHelper.defaultHelper.preferredBoldFont(withTextStyle: .caption1,
                                                            size: UX.siteFontSize)

        sponsoredStack.isHidden  = viewModel.shouldHideSponsor

        adjustLayout()
        applyTheme(theme: theme)
    }

    private func setupLayout() {
        contentView.layer.cornerRadius = UX.generalCornerRadius
        contentView.addSubviews(titleLabel, heroImageView)
        sponsoredStack.addArrangedSubview(sponsoredIcon)
        sponsoredStack.addArrangedSubview(sponsoredLabel)
        bottomTextStackView.addArrangedSubview(sponsoredStack)
        bottomTextStackView.addArrangedSubview(descriptionLabel)
        contentView.addSubview(bottomTextStackView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.horizontalMargin),
            titleLabel.leadingAnchor.constraint(equalTo: heroImageView.trailingAnchor,
                                                constant: UX.horizontalMargin),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                 constant: -UX.horizontalMargin),

            heroImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                   constant: UX.horizontalMargin),
            heroImageView.heightAnchor.constraint(equalToConstant: UX.heroImageSize.height),
            heroImageView.widthAnchor.constraint(equalToConstant: UX.heroImageSize.width),
            heroImageView.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            heroImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor,
                                                  constant: -UX.horizontalMargin),

            // Sponsored
            bottomTextStackView.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: 8),
            bottomTextStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bottomTextStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                       constant: -UX.horizontalMargin),
            bottomTextStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor,
                                                     constant: -UX.horizontalMargin),

            sponsoredIcon.heightAnchor.constraint(equalToConstant: UX.sponsoredIconSize.height),
            sponsoredIcon.widthAnchor.constraint(equalToConstant: UX.sponsoredIconSize.width),
        ])
    }

    private func adjustLayout() {
        let contentSizeCategory = UIApplication.shared.preferredContentSizeCategory

        // Center favicon on smaller font sizes. On bigger font sizes align with first baseline
        sponsoredImageCenterConstraint?.isActive = !contentSizeCategory.isAccessibilityCategory
        sponsoredImageFirstBaselineConstraint?.isActive = contentSizeCategory.isAccessibilityCategory
    }

    private func setupShadow(theme: Theme) {
        contentView.layer.cornerRadius = UX.generalCornerRadius
        contentView.layer.shadowPath = UIBezierPath(roundedRect: contentView.bounds,
                                                    cornerRadius: UX.generalCornerRadius).cgPath
        contentView.layer.shadowRadius = HomepageViewModel.UX.shadowRadius
        contentView.layer.shadowOffset = HomepageViewModel.UX.shadowOffset
        contentView.layer.shadowColor = theme.colors.shadowDefault.cgColor
        contentView.layer.shadowOpacity = HomepageViewModel.UX.shadowOpacity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.shadowPath = UIBezierPath(roundedRect: contentView.bounds,
                                                    cornerRadius: UX.generalCornerRadius).cgPath
    }
}

// MARK: - Blurrable
extension PocketStandardCell: Blurrable {
    func adjustBlur(theme: Theme) {
        // Add blur
        if shouldApplyWallpaperBlur {
            contentView.addBlurEffectWithClearBackgroundAndClipping(using: .systemThickMaterial)
        } else {
            contentView.removeVisualEffectView()
            contentView.backgroundColor = theme.colors.layer5
            setupShadow(theme: theme)
        }
    }
}

// MARK: - ThemeApplicable
extension PocketStandardCell: ThemeApplicable {
    func applyTheme(theme: Theme) {
        titleLabel.textColor = theme.colors.textPrimary
        descriptionLabel.textColor = theme.colors.textSecondary
        sponsoredLabel.textColor = theme.colors.textSecondary

        adjustBlur(theme: theme)
    }
}

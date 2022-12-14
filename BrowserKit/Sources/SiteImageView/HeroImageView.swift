// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit
import Common

/// HeroImageView supports the hero image layout.
/// By setting the view model, the image will be updated for you asynchronously.
///
/// - Hero image with a favicon fallback. Any time you set a hero image, if it's not found it will default to a favicon image.
///     - Can be set through `setHeroImage(_ viewModel: SiteImageViewHeroImageModel)`
///     - The layout size is set through the properties of SiteImageViewHeroImageModel
///     - Need to setup theme calls through `updateHeroImageTheme(with colors: SiteImageViewColor)`
public class HeroImageView: UIView, SiteImageView {
    // MARK: - Properties
    var uniqueID: UUID?
    var imageFetcher: SiteImageFetcher
    var requestStartedWith: String?
    private var completionHandler: (() -> Void)?

    private lazy var heroImageView: UIImageView = .build { imageView in
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = .clear
    }

    // Used as a fallback if hero image isn't set
    private lazy var fallbackFaviconImageView: UIImageView = .build { imageView in
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        imageView.layer.masksToBounds = true
    }

    private lazy var fallbackFaviconBackground: UIView = .build { view in }

    // MARK: - Init

    public override init(frame: CGRect) {
        self.imageFetcher = DefaultSiteImageFetcher()
        super.init(frame: frame)
    }

    // Internal init used in unit tests only
    init(frame: CGRect,
         imageFetcher: SiteImageFetcher,
         completionHandler: @escaping () -> Void) {
        self.imageFetcher = imageFetcher
        self.completionHandler = completionHandler
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    public func setHeroImage(_ viewModel: HeroImageViewModel) {
        setupHeroImageLayout(viewModel: viewModel)
        setURL(viewModel.siteURL, type: viewModel.type)
    }

    public func updateHeroImageTheme(with colors: HeroImageViewColor) {
        fallbackFaviconImageView.tintColor = colors.faviconTintColor
        fallbackFaviconBackground.backgroundColor = colors.faviconBackgroundColor
        fallbackFaviconBackground.layer.borderColor = colors.faviconBorderColor.cgColor
    }

    // MARK: - SiteImageView

    func setURL(_ urlStringRequest: String, type: SiteImageType) {
        guard canMakeRequest(with: urlStringRequest) else { return }

        let id = UUID()
        uniqueID = id
        updateImage(url: urlStringRequest, type: type, id: id)
    }

    func setImage(imageModel: SiteImageModel) {
        setHeroImage(imageModel: imageModel)
        completionHandler?()
    }

    // MARK: - Hero image

    private func setHeroImage(imageModel: SiteImageModel) {
        if let heroImage = imageModel.heroImage {
            // If hero image is a square use it as a favicon
            guard heroImage.size.width == heroImage.size.height else {
                setHeroImage(image: heroImage)
                return
            }
            setFallbackFavicon(image: heroImage)
        } else if let faviconImage = imageModel.faviconImage {
            setFallbackFavicon(image: faviconImage)
        }
    }

    private func setupHeroImageLayout(viewModel: HeroImageViewModel) {
        heroImageView.layer.cornerRadius = viewModel.generalCornerRadius
        fallbackFaviconImageView.layer.cornerRadius = viewModel.faviconCornerRadius
        fallbackFaviconBackground.layer.cornerRadius = viewModel.generalCornerRadius
        fallbackFaviconBackground.layer.borderWidth = viewModel.faviconBorderWidth

        fallbackFaviconBackground.addSubview(fallbackFaviconImageView)
        addSubviews(heroImageView, fallbackFaviconBackground)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: viewModel.heroImageSize.height),
            widthAnchor.constraint(equalToConstant: viewModel.heroImageSize.width),

            heroImageView.topAnchor.constraint(equalTo: topAnchor),
            heroImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            heroImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heroImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            fallbackFaviconBackground.centerXAnchor.constraint(equalTo: centerXAnchor),
            fallbackFaviconBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            fallbackFaviconBackground.heightAnchor.constraint(equalToConstant: viewModel.heroImageSize.height),
            fallbackFaviconBackground.widthAnchor.constraint(equalToConstant: viewModel.heroImageSize.width),

            fallbackFaviconImageView.heightAnchor.constraint(equalToConstant: viewModel.fallbackFaviconSize.height),
            fallbackFaviconImageView.widthAnchor.constraint(equalToConstant: viewModel.fallbackFaviconSize.width),
            fallbackFaviconImageView.centerXAnchor.constraint(equalTo: fallbackFaviconBackground.centerXAnchor),
            fallbackFaviconImageView.centerYAnchor.constraint(equalTo: fallbackFaviconBackground.centerYAnchor),
        ])
    }

    // MARK: - Conveniance methods

    private func setHeroImage(image: UIImage) {
        setFallBackFaviconVisibility(isHidden: true)
        heroImageView.image = image
    }

    private func setFallbackFavicon(image: UIImage) {
        setFallBackFaviconVisibility(isHidden: false)
        fallbackFaviconImageView.image = image
    }

    private func setFallBackFaviconVisibility(isHidden: Bool) {
        fallbackFaviconBackground.isHidden = isHidden
        fallbackFaviconImageView.isHidden = isHidden
    }
}

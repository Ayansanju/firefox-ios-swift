// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit

protocol ImageHandler {

    /// The ImageHandler will fetch the favicon with the following precedence:
    ///     1. Tries to fetch from the bundle.
    ///     2. Tries to fetch from the cache.
    ///     3. Tries to fetch from the image fetcher (from the web) if there's a URL. If there's no URL it fallbacks to the letter favicon.
    ///     4. When all fails it returns the letter favicon.
    ///
    /// Any time the favicon is fetched, it will be cache for future usage.
    ///
    /// - Parameters:
    ///   - imageURL: The image URL, can be nil if it could not be retrieved from the site
    ///   - domain: The domain this favicon will be associated with
    /// - Returns: The favicon image
    func fetchFavicon(imageURL: URL?,
                      domain: String) async throws -> UIImage

    /// The ImageHandler will fetch the hero image with the following precedence
    ///     1. Tries to fetch from the cache.
    ///     2. Tries to fetch from the hero image fetcher (from the web).
    ///     3. If all fails it throws an error
    ///
    /// Any time the hero image  is fetched, it will be cache for future usage.
    /// - Parameters:
    ///   - siteURL: The site URL to fetch the hero image from
    ///   - domain: The domain this hero image will be associated with
    /// - Returns: The hero image
    func fetchHeroImage(siteURL: URL,
                        domain: String) async throws -> UIImage
}

class DefaultImageHandler: ImageHandler {

    private let bundleImageFetcher: BundleImageFetcher
    private let imageCache: SiteImageCache
    private let imageFetcher: SiteImageFetcher
    private let letterImageGenerator: LetterImageGenerator
    private let heroImageFetcher: HeroImageFetcher

    init(bundleImageFetcher: BundleImageFetcher = DefaultBundleImageFetcher(),
         imageCache: SiteImageCache = DefaultSiteImageCache(),
         imageFetcher: SiteImageFetcher = DefaultSiteImageFetcher(),
         letterImageGenerator: LetterImageGenerator = DefaultLetterImageGenerator(),
         heroImageFetcher: HeroImageFetcher = DefaultHeroImageFetcher()) {
        self.bundleImageFetcher = bundleImageFetcher
        self.imageCache = imageCache
        self.imageFetcher = imageFetcher
        self.letterImageGenerator = letterImageGenerator
        self.heroImageFetcher = heroImageFetcher
    }

    func fetchFavicon(imageURL: URL?,
                      domain: String) async throws -> UIImage {
        do {
            return try bundleImageFetcher.getImageFromBundle(domain: domain)
        } catch {
            return try await fetchFaviconFromCache(imageURL: imageURL, domain: domain)
        }
    }

    func fetchHeroImage(siteURL: URL,
                        domain: String) async throws -> UIImage {
        do {
            return try await imageCache.getImageFromCache(domain: domain, type: .heroImage)
        } catch {
            return try await fetchHeroImageFromFetcher(siteURL: siteURL, domain: domain)
        }
    }

    // MARK: Private

    private func fetchFaviconFromCache(imageURL: URL?,
                                       domain: String) async throws -> UIImage {
        do {
            return try await imageCache.getImageFromCache(domain: domain, type: .favicon)
        } catch {
            return try await fetchFaviconFromFetcher(imageURL: imageURL, domain: domain)
        }
    }

    private func fetchFaviconFromFetcher(imageURL: URL?,
                                         domain: String) async throws -> UIImage {
        do {
            guard let url = imageURL else {
                return await fallbackToLetterFavicon(domain: domain)
            }

            let image = try await imageFetcher.fetchImage(from: url)
            await imageCache.cacheImage(image: image, domain: domain, type: .favicon)
            return image

        } catch {
            return await fallbackToLetterFavicon(domain: domain)
        }
    }

    private func fetchHeroImageFromFetcher(siteURL: URL,
                                           domain: String) async throws -> UIImage {
        do {
            let image = try await heroImageFetcher.fetchHeroImage(from: siteURL)
            await imageCache.cacheImage(image: image, domain: domain, type: .heroImage)
            return image

        } catch {
            throw SiteImageError.noHeroImage
        }
    }

    private func fallbackToLetterFavicon(domain: String) async -> UIImage {
        let image = letterImageGenerator.generateLetterImage(domain: domain)
        await imageCache.cacheImage(image: image, domain: domain, type: .favicon)
        return image
    }
}

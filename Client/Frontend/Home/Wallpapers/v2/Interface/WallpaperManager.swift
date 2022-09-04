// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit

protocol WallpaperManagerInterface {
    var currentWallpaper: Wallpaper? { get }
    var availableCollections: [WallpaperCollection] { get }
    var canOnboardingBeShown: Bool { get }

    func setCurrentWallpaper(to wallpaper: Wallpaper, completion: @escaping (Result<Void, Error>) -> Void)
    func fetch(_ wallpaper: Wallpaper, completion: @escaping (Result<Void, Error>) -> Void)
    func removeDownloadedAssets()
    func checkForUpdates()
}

/// The primary interface for the wallpaper feature.
class WallpaperManager: WallpaperManagerInterface, FeatureFlaggable, Loggable {

    // MARK: - Properties
    private var networkingModule: WallpaperNetworking

    // MARK: - Initializers
    init(with networkingModule: WallpaperNetworking = WallpaperNetworkingModule()) {
        self.networkingModule = networkingModule
    }

    // MARK: Public Interface

    /// Returns the currently selected wallpaper.
    public var currentWallpaper: Wallpaper? {
        do {
            let storageUtility = WallpaperStorageUtility()
            return try storageUtility.fetchCurrentWallpaper()
        } catch {
            browserLog.error("WallpaperManager error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns all available collections and their wallpaper data. Availability is
    /// determined on locale and date ranges from the collection's metadata.
    public var availableCollections: [WallpaperCollection] {
        return getAvailableCollections()
    }

    /// Determines whether the wallpaper onboarding can be shown
    var canOnboardingBeShown: Bool {
        let thumbnailUtility = WallpaperThumbnailUtility(with: networkingModule)

        guard let wallpaperVersion: WallpaperVersion = featureFlags.getCustomState(for: .wallpaperVersion),
              wallpaperVersion == .v2,
              featureFlags.isFeatureEnabled(.wallpaperOnboardingSheet, checking: .buildOnly),
              thumbnailUtility.areThumbnailsAvailable
        else { return false }

        return true
    }

    /// Sets and saves a selected wallpaper as currently selected wallpaper.
    ///
    /// - Parameter wallpaper: A `Wallpaper` the user has selected.
    public func setCurrentWallpaper(
        to wallpaper: Wallpaper,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let storageUtility = WallpaperStorageUtility()
            try storageUtility.store(wallpaper)

            completion(.success(()))

        } catch {
            browserLog.error("Failed to set wallpaper: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }

    /// Fetches the images for a specific wallpaper.
    ///
    /// - Parameter wallpaper: A `Wallpaper` for which images should be downloaded.
    /// - Parameter completion: The block that is called when the image download completes.
    ///                      If the images is loaded successfully, the block is called with
    ///                      a `.success` with the data associated. Otherwise, it is called
    ///                      with a `.failure` and passed an error.
    func fetch(_ wallpaper: Wallpaper, completion: @escaping (Result<Void, Error>) -> Void) {
        let dataService = WallpaperDataService(with: networkingModule)
        let storageUtility = WallpaperStorageUtility()

        Task(priority: .userInitiated) {

            do {
                // Download both images at the same time for efficiency
                async let portraitFetchRequest = dataService.getImageWith(
                    key: wallpaper.id,
                    imageName: wallpaper.portraitID)
                async let landscapeFetchRequest = dataService.getImageWith(
                    key: wallpaper.id,
                    imageName: wallpaper.landscapeID)

                let (portrait, landscape) = await (try portraitFetchRequest,
                                                   try landscapeFetchRequest)

                try storageUtility.store(portrait, withName: wallpaper.portraitID, andKey: wallpaper.id)
                try storageUtility.store(landscape, withName: wallpaper.landscapeID, andKey: wallpaper.id)

                completion(.success(()))
            } catch {
                browserLog.error("Error fetching wallpaper resources: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    public func removeDownloadedAssets() {
        let storageUtility = WallpaperStorageUtility()
        try? storageUtility.removeUnusedLargeWallpaperFiles()
    }

    /// Reaches out to the server and fetches the latest metadata. This is then compared
    /// to existing metadata, and, if there are changes, performs the necessary operations
    /// to ensure parity between server data and what the user sees locally.
    public func checkForUpdates() {
        let thumbnailUtility = WallpaperThumbnailUtility(with: networkingModule)
        let metadataUtility = WallpaperMetadataUtility(with: networkingModule)

        Task {
            let didFetchNewData = await metadataUtility.metadataUpdateFetchedNewData()
            if didFetchNewData {
                do {
                    let migrationUtility = WallpaperMigrationUtility()
                    migrationUtility.attemptMigration()

                    try await thumbnailUtility.fetchAndVerifyThumbnails(for: availableCollections)
                } catch {
                    browserLog.error("Wallpaper update check error: \(error.localizedDescription)")
                }
            } else {
                thumbnailUtility.verifyThumbnailsFor(availableCollections)
            }
        }
    }

    // MARK: - Helper functions
    private func getAvailableCollections() -> [WallpaperCollection] {
        guard let metadata = getMetadata() else { return [] }

        let collections = metadata.collections.filter {
            let isDateAvailable = $0.availability?.isAvailable ?? true
            var isLocaleAvailable: Bool = false

            if let availableLocales = $0.availableLocales {
                isLocaleAvailable = availableLocales.isEmpty || availableLocales.contains(Locale.current.identifier)
            } else {
                isLocaleAvailable = true
            }

            return isDateAvailable && isLocaleAvailable
        }

        let collectionsWithDefault = addDefaultWallpaper(to: collections)
        return collectionsWithDefault
    }

    private func addDefaultWallpaper(to availableCollections: [WallpaperCollection]) -> [WallpaperCollection] {
        guard let classicCollection = availableCollections.first(where: { $0.type == .classic }) else { return availableCollections }

        let defaultWallpaper = [Wallpaper(id: "fxDefault",
                                          textColour: nil,
                                          cardColour: nil)]
        let newWallpapers = defaultWallpaper + classicCollection.wallpapers
        let newClassic = WallpaperCollection(id: classicCollection.id,
                                             learnMoreURL: classicCollection.learnMoreUrl?.absoluteString,
                                             availableLocales: classicCollection.availableLocales,
                                             availability: classicCollection.availability,
                                             wallpapers: newWallpapers,
                                             description: classicCollection.description,
                                             heading: classicCollection.heading)

        return [newClassic] + availableCollections.filter { $0.type != .classic }
    }

    private func getMetadata() -> WallpaperMetadata? {
        let metadataUtility = WallpaperMetadataUtility(with: networkingModule)
        do {
            guard let metadata = try metadataUtility.getMetadata() else { return nil }

            return metadata
        } catch {
            browserLog.error("Error getting stored metadata: \(error.localizedDescription)")
            return nil
        }
    }
}

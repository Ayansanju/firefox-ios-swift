// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

protocol WallpaperMetadataTrackerProtocol {
    func metadataUpdateFetchedNewData() async -> Bool
}

/// Responsible for tracking whether or not the wallpaper system should perform
/// a variety of checks, such as whether it should fetch data from the server.
class WallpaperMetadataTracker: WallpaperMetadataTrackerProtocol, Loggable {

    // MARK: - Properties

    /// Will return `true` under two conditions:
    /// 1. Has never performed a check
    /// 2. Has not performed a check on the current day
    private var shouldCheckForNewMetadata: Bool {
        guard let existingDate = userDefaults.object(forKey: prefsKey) as? Date else { return true }
        let todaysDate = Calendar.current.startOfDay(for: Date())

        if existingDate == todaysDate { return false }

        return true
    }

    private let prefsKey = PrefsKeys.Wallpapers.MetadataLastCheckedDate

    private let userDefaults: UserDefaultsInterface
    private let networkingModule: WallpaperNetworking

    // MARK: - Initializers
    init(
        with userDefaults: UserDefaultsInterface = UserDefaults.standard,
        and networkingModule: WallpaperNetworking
    ) {
        self.userDefaults = userDefaults
        self.networkingModule = networkingModule
    }

    deinit {

    }

    // MARK: - Public interface
    public func metadataUpdateFetchedNewData() async -> Bool {
        if !shouldCheckForNewMetadata { return false }
        return await attemptToFetchMetadata()
    }

    // MARK: - Private methods
    private func attemptToFetchMetadata() async -> Bool {
        do {
            let metadata = try await fetchMetadata()
            return true

        } catch {
            browserLog.error("Failed to fetch new metadata: \(error.localizedDescription)")
            return false
        }
    }
    private func fetchMetadata() async throws -> WallpaperMetadata {
        let dataService = WallpaperDataService(with: networkingModule)
        return try await dataService.getMetadata()
    }
}

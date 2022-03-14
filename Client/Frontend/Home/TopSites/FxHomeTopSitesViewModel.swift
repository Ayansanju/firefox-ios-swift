// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
import Storage

protocol FxHomeTopSitesViewModelDelegate: AnyObject {
    func reloadTopSites()
}

// TODO: Laurie - fix pins images not working
// TODO: Laurie - fix layout when changing from home settings (2 to 4 fours for example)
class FxHomeTopSitesViewModel {

    struct UX {
        static let numberOfItemsPerRowForSizeClassIpad = UXSizeClasses(compact: 3, regular: 4, other: 2)
        static let interItemSpacing: CGFloat = 25
    }

    private let profile: Profile
    private let experiments: NimbusApi
    private let isZeroSearch: Bool

    typealias SectionDimension = (numberOfRows: Int, numberOfTilesPerRow: Int)
    var sectionDimension: FxHomeTopSitesViewModel.SectionDimension = FxHomeTopSitesViewModel.defaultDimension
    static var defaultDimension: FxHomeTopSitesViewModel.SectionDimension = (6, 2)

    var tilePressedHandler: ((Site, Bool) -> Void)?
    var tileLongPressedHandler: ((IndexPath) -> Void)?
    var tileManager: FxHomeTopSitesManager
    weak var delegate: FxHomeTopSitesViewModelDelegate?

    // Need to save the parent's section for the long press action
    // since it's currently handled in FirefoxHomeViewController
    // TODO: Each section should handle the long press details - not the parent
    var topSitesShownInSection: Int = 0

    private lazy var homescreen = experiments.withVariables(featureId: .homescreen, sendExposureEvent: false) {
        Homescreen(variables: $0)
    }

    init(profile: Profile, experiments: NimbusApi, isZeroSearch: Bool) {
        self.profile = profile
        self.experiments = experiments
        self.isZeroSearch = isZeroSearch
        self.tileManager = FxHomeTopSitesManager(profile: profile)
        tileManager.delegate = self
    }

    func getSectionDimension(for trait: UITraitCollection) -> SectionDimension {
        let numberOfTilesPerRow = getNumberOfTilesPerRow(for: trait)
        let numberOfRows = getNumberOfRows(numberOfTilesPerRow: numberOfTilesPerRow)
        return SectionDimension(numberOfRows, numberOfTilesPerRow)
    }

    // The dimension of a cell
    static func widthDimension(for numberOfHorizontalItems: Int) -> NSCollectionLayoutDimension {
        return .fractionalWidth(CGFloat(1/numberOfHorizontalItems))
    }

    // TODO: Laurie - write tests for this
    // Adjust number of rows depending on the what the users want, and how many sites we actually have.
    // We hide rows that are only composed of empty cells
    private func getNumberOfRows(numberOfTilesPerRow: Int) -> Int {
        if tileManager.siteCount % numberOfTilesPerRow == 0 {
            return tileManager.numberOfRows
        } else {
            return Int((Double(tileManager.siteCount) / Double(tileManager.numberOfRows)).rounded(.down))
        }
    }

    private func getNumberOfTilesPerRow(for trait: UITraitCollection) -> Int {
        let isLandscape = UIWindow.isLandscape
        if UIDevice.current.userInterfaceIdiom == .phone {
            if isLandscape {
                print("Laurie - numItems: 8")
                return 8
            } else {
                print("Laurie - numItems: 4")
                return 4
            }
        } else {
            // The number of items in a row is equal to the number of top sites in a row * 2
            var numItems = Int(UX.numberOfItemsPerRowForSizeClassIpad[trait.horizontalSizeClass])
            if UIWindow.isPortrait || (trait.horizontalSizeClass == .compact && isLandscape) {
                numItems = numItems - 1
            }
            print("Laurie - numItems:\(numItems)")
            return numItems * 2
        }
    }

    func reloadData(for trait: UITraitCollection) {
        sectionDimension = getSectionDimension(for: trait)
        tileManager.calculateTopSiteData(numberOfTilesPerRow: sectionDimension.numberOfTilesPerRow)
    }

    func tilePressed(site: HomeTopSite, position: Int) {
        topSiteTracking(site: site, position: position)
        tilePressedHandler?(site.site, site.isGoogleURL)
    }

    func topSiteTracking(site: HomeTopSite, position: Int) {
        // Top site extra
        let topSitePositionKey = TelemetryWrapper.EventExtraKey.topSitePosition.rawValue
        let topSiteTileTypeKey = TelemetryWrapper.EventExtraKey.topSiteTileType.rawValue
        let isPinnedAndGoogle = site.isPinned && site.isGoogleGUID
        let type = isPinnedAndGoogle ? "google" : site.isPinned ? "user-added" : site.isSuggested ? "suggested" : "history-based"
        let topSiteExtra = [topSitePositionKey : "\(position)", topSiteTileTypeKey: type]

        // Origin extra
        let originExtra = TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch)
        let extras = originExtra.merge(with: topSiteExtra)

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .topSiteTile,
                                     value: nil,
                                     extras: extras)
    }

    // MARK: Context actions

    func getTopSitesAction(site: Site) -> [PhotonRowActions]{
        let removeTopSiteAction = SingleActionViewModel(title: .RemoveContextMenuTitle,
                                                        iconString: ImageIdentifiers.actionRemove,
                                                        tapHandler: { _ in
            self.hideURLFromTopSites(site)
        }).items

        let pinTopSite = SingleActionViewModel(title: .AddToShortcutsActionTitle,
                                               iconString: ImageIdentifiers.addShortcut,
                                               tapHandler: { _ in
            self.pinTopSite(site)
        }).items

        let removePinTopSite = SingleActionViewModel(title: .RemoveFromShortcutsActionTitle,
                                                     iconString: ImageIdentifiers.removeFromShortcut,
                                                     tapHandler: { _ in
            self.removePinTopSite(site)
        }).items

        let topSiteActions: [PhotonRowActions]
        if let _ = site as? PinnedSite {
            topSiteActions = [removePinTopSite]
        } else {
            topSiteActions = [pinTopSite, removeTopSiteAction]
        }
        return topSiteActions
    }

    private func hideURLFromTopSites(_ site: Site) {
        guard let host = site.tileURL.normalizedHost else { return }

        let url = site.tileURL.absoluteString
        // if the default top sites contains the siteurl. also wipe it from default suggested sites.
        if !defaultTopSites().filter({ $0.url == url }).isEmpty {
            deleteTileForSuggestedSite(url)
        }

        profile.history.removeHostFromTopSites(host).uponQueue(.main) { result in
            guard result.isSuccess else { return }
            self.tileManager.refreshIfNeeded(forceTopSites: true)
        }
    }

    private func pinTopSite(_ site: Site) {
        profile.history.addPinnedTopSite(site).uponQueue(.main) { result in
            guard result.isSuccess else { return }
            self.tileManager.refreshIfNeeded(forceTopSites: true)
        }
    }

    func removePinTopSite(_ site: Site) {
        tileManager.removePinTopSite(site: site)
    }

    private func deleteTileForSuggestedSite(_ siteURL: String) {
        var deletedSuggestedSites = profile.prefs.arrayForKey(TopSitesHelper.DefaultSuggestedSitesKey) as? [String] ?? []
        deletedSuggestedSites.append(siteURL)
        profile.prefs.setObject(deletedSuggestedSites, forKey: TopSitesHelper.DefaultSuggestedSitesKey)
    }

    private func defaultTopSites() -> [Site] {
        let suggested = SuggestedSites.asArray()
        let deleted = profile.prefs.arrayForKey(TopSitesHelper.DefaultSuggestedSitesKey) as? [String] ?? []
        return suggested.filter({ deleted.firstIndex(of: $0.url) == .none })
    }
}

// MARK: FXHomeViewModelProtocol
extension FxHomeTopSitesViewModel: FXHomeViewModelProtocol, FeatureFlagsProtocol {

    var sectionType: FirefoxHomeSectionType {
        return .topSites
    }

    var isEnabled: Bool {
        homescreen.sectionsEnabled[.topSites] == true
    }

    var hasData: Bool {
        return tileManager.hasData
    }

    func updateData(completion: @escaping () -> Void) {
        tileManager.loadTopSitesData()
    }
}

// MARK: FxHomeTopSitesManagerDelegate
extension FxHomeTopSitesViewModel: FxHomeTopSitesManagerDelegate {
    func reloadTopSites() {
        delegate?.reloadTopSites()
    }
}

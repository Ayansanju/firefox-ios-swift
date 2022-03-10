// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import MozillaAppServices

protocol FirefoxHomeViewModelDelegate: AnyObject {
    func reloadSection(index: Int?)
}

class FirefoxHomeViewModel: FeatureFlagsProtocol {

    struct UX {
        static let homeHorizontalCellHeight: CGFloat = 120
        static let recentlySavedCellHeight: CGFloat = 136
        static let historyHighlightsCellHeight: CGFloat = 68
        static let topSitesCellHeight: CGFloat = 100
        static let sectionInsetsForSizeClass = UXSizeClasses(compact: 0, regular: 101, other: 15)
        static let spacingBetweenSections: CGFloat = 24
        static let sectionInsetsForIpad: CGFloat = 101
        static let minimumInsets: CGFloat = 15
        static let libraryShortcutsHeight: CGFloat = 90
        static let libraryShortcutsMaxWidth: CGFloat = 375
        static let customizeHomeHeight: CGFloat = 100
        static let logoHeaderHeight: CGFloat = 85
    }

    // MARK: - Properties
    
    // Privacy of home page is controlled throught notifications since tab manager selected tab
    // isn't always the proper privacy mode that should be reflected on the home page
    var isPrivate: Bool {
        didSet {
            childViewModels.forEach {
                $0.updatePrivacyConcernedSection(isPrivate: isPrivate)
            }
        }
    }
    let experiments: NimbusApi
    let profile: Profile
    var isZeroSearch: Bool
    var enabledSections = [FirefoxHomeSectionType]()
    weak var delegate: FirefoxHomeViewModelDelegate?

    // Child View models
    private var childViewModels: [FXHomeViewModelProtocol]
    var headerViewModel: FxHomeLogoHeaderViewModel
    var topSiteViewModel: FxHomeTopSitesViewModel
    var recentlySavedViewModel: FirefoxHomeRecentlySavedViewModel
    var jumpBackInViewModel: FirefoxHomeJumpBackInViewModel
    var historyHighlightsViewModel: FxHomeHistoryHightlightsViewModel
    var pocketViewModel: FxHomePocketViewModel

    private lazy var homescreen = experiments.withVariables(featureId: .homescreen, sendExposureEvent: false) {
        Homescreen(variables: $0)
    }

    // MARK: - Section availability variables

    var isYourLibrarySectionEnabled: Bool {
        UIDevice.current.userInterfaceIdiom != .pad &&
            homescreen.sectionsEnabled[.libraryShortcuts] == true
    }

    // MARK: - Initializers
    init(profile: Profile,
         isZeroSearch: Bool = false,
         isPrivate: Bool,
         experiments: NimbusApi) {
        self.profile = profile
        self.isZeroSearch = isZeroSearch

        self.headerViewModel = FxHomeLogoHeaderViewModel(profile: profile)
        self.topSiteViewModel = FxHomeTopSitesViewModel(profile: profile, experiments: experiments, isZeroSearch: isZeroSearch)
        self.jumpBackInViewModel = FirefoxHomeJumpBackInViewModel(isZeroSearch: isZeroSearch, profile: profile, experiments: experiments, isPrivate: isPrivate)
        self.recentlySavedViewModel = FirefoxHomeRecentlySavedViewModel(isZeroSearch: isZeroSearch, profile: profile, experiments: experiments)
        self.historyHighlightsViewModel = FxHomeHistoryHightlightsViewModel(with: profile, isPrivate: isPrivate)
        self.pocketViewModel = FxHomePocketViewModel(profile: profile, isZeroSearch: isZeroSearch)
        self.childViewModels = [headerViewModel, topSiteViewModel, jumpBackInViewModel, recentlySavedViewModel, historyHighlightsViewModel, pocketViewModel]

        self.experiments = experiments
        self.isPrivate = isPrivate
    }
    
    // MARK: - Interfaces

    func updateData() {
        childViewModels.forEach {
            guard $0.isComformanceUpdateDataReady else { return }
            if $0.isEnabled { $0.updateData {} }
        }

        // Following code is for sections not isComformanceUpdateDataReady

        // Jump back in access tabManager and this needs to be done on the main thread at the moment
        DispatchQueue.main.async {
            if self.jumpBackInViewModel.isEnabled {
                self.jumpBackInViewModel.updateData {}
            }
        }

        if pocketViewModel.isEnabled {
            pocketViewModel.updateData {
                let index = self.enabledSections.firstIndex(of: FirefoxHomeSectionType.jumpBackIn)
                self.delegate?.reloadSection(index: index)
            }
        }

        if historyHighlightsViewModel.isEnabled {
            historyHighlightsViewModel.updateData {
                let index = self.enabledSections.firstIndex(of: FirefoxHomeSectionType.historyHighlights)
                self.delegate?.reloadSection(index: index)
            }
        }
    }
    
    func updateEnabledSections() {
        enabledSections.removeAll()

        childViewModels.forEach {
            if $0.shouldShow { enabledSections.append($0.sectionType) }
        }

        // Sections that have no view model yet
        // please remove when they have a view model and comform to FXHomeViewModelProtocol
        for section in FirefoxHomeSectionType.allCases {
            switch section {
            case .libraryShortcuts:
                if isYourLibrarySectionEnabled {
                    enabledSections.append(.libraryShortcuts)
                }
            case .customizeHome:
                enabledSections.append(.customizeHome)
            default:
                break
            }
        }
    }
}

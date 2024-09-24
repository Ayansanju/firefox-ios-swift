// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import MenuKit
import Shared
import Redux

struct MainMenuTabInfo: Equatable {
    let url: URL?
    let isHomepage: Bool
    let isDefaultUserAgentDesktop: Bool
    let hasChangedUserAgent: Bool
}

struct MainMenuState: ScreenState, Equatable {
    var windowUUID: WindowUUID
    var menuElements: [MenuSection]

    var shouldDismiss: Bool
    var shouldShowDetailsView: Bool

    var navigationDestination: MenuNavigationDestination?
    var currentTabInfo: MainMenuTabInfo?

    private let menuConfigurator = MainMenuConfigurationUtility()

    init(appState: AppState, uuid: WindowUUID) {
        guard let mainMenuState = store.state.screenState(
            MainMenuState.self,
            for: .mainMenu,
            window: uuid
        ) else {
            self.init(windowUUID: uuid)
            return
        }

        self.init(
            windowUUID: mainMenuState.windowUUID,
            menuElements: mainMenuState.menuElements,
            currentTabInfo: mainMenuState.currentTabInfo,
            navigationDestination: mainMenuState.navigationDestination,
            shouldDismiss: mainMenuState.shouldDismiss,
            shouldShowDetailsView: mainMenuState.shouldShowDetailsView
        )
    }

    init(windowUUID: WindowUUID) {
        self.init(
            windowUUID: windowUUID,
            menuElements: [],
            currentTabInfo: nil,
            navigationDestination: nil,
            shouldDismiss: false,
            shouldShowDetailsView: false
        )
    }

    private init(
        windowUUID: WindowUUID,
        menuElements: [MenuSection],
        currentTabInfo: MainMenuTabInfo?,
        navigationDestination: MenuNavigationDestination? = nil,
        shouldDismiss: Bool = false,
        shouldShowDetailsView: Bool = false
    ) {
        self.windowUUID = windowUUID
        self.menuElements = menuElements
        self.currentTabInfo = currentTabInfo
        self.navigationDestination = navigationDestination
        self.shouldDismiss = shouldDismiss
        self.shouldShowDetailsView = shouldShowDetailsView
    }

    static let reducer: Reducer<Self> = { state, action in
        guard action.windowUUID == .unavailable || action.windowUUID == state.windowUUID else { return state }
        guard let action = action as? MainMenuAction else { return state }

        switch action.actionType {
        case MainMenuActionType.viewDidLoad:
            return MainMenuState(
                windowUUID: state.windowUUID,
                menuElements: state.menuElements,
                currentTabInfo: state.currentTabInfo
            )
        case MainMenuActionType.updateCurrentTabInfo:
            return MainMenuState(
                windowUUID: state.windowUUID,
                menuElements: state.menuConfigurator.generateMenuElements(
                    with: state.windowUUID,
                    andInfo: action.currentTabInfo
                ),
                currentTabInfo: action.currentTabInfo
            )
        case MainMenuActionType.navigate:
            return MainMenuState(
                windowUUID: state.windowUUID,
                menuElements: state.menuElements,
                currentTabInfo: state.currentTabInfo,
                navigationDestination: action.navigationDestination
            )
        case MainMenuActionType.toggleUserAgent,
            MainMenuActionType.closeMenu:
            return MainMenuState(
                windowUUID: state.windowUUID,
                menuElements: state.menuElements,
                currentTabInfo: state.currentTabInfo,
                shouldDismiss: true
            )
        default:
            return MainMenuState(
                windowUUID: state.windowUUID,
                menuElements: state.menuElements,
                currentTabInfo: state.currentTabInfo
            )
        }
    }
}

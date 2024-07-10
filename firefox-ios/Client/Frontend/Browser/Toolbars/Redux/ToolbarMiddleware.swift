// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import ToolbarKit

class ToolbarMiddleware: FeatureFlaggable {
    private let profile: Profile
    private let manager: ToolbarManager
    private let logger: Logger

    init(profile: Profile = AppContainer.shared.resolve(),
         manager: ToolbarManager = DefaultToolbarManager(),
         logger: Logger = DefaultLogger.shared) {
        self.profile = profile
        self.manager = manager
        self.logger = logger
    }

    lazy var toolbarProvider: Middleware<AppState> = { state, action in
        if let action = action as? GeneralBrowserMiddlewareAction {
            self.resolveGeneralBrowserMiddlewareActions(action: action, state: state)
        } else if let action = action as? ToolbarMiddlewareAction {
            self.resolveToolbarMiddlewareActions(action: action, state: state)
        }
    }

    lazy var stopLoadingAction = ToolbarActionState(
        actionType: .stopLoading,
        iconName: StandardImageIdentifiers.Large.cross,
        isEnabled: true,
        a11yLabel: .TabToolbarStopAccessibilityLabel,
        a11yId: AccessibilityIdentifiers.Toolbar.stopButton)

    lazy var reloadAction = ToolbarActionState(
        actionType: .reload,
        iconName: StandardImageIdentifiers.Large.arrowClockwise,
        isEnabled: true,
        a11yLabel: .TabLocationReloadAccessibilityLabel,
        a11yHint: .TabLocationReloadAccessibilityHint,
        a11yId: AccessibilityIdentifiers.Toolbar.reloadButton)

    lazy var qrCodeScanAction = ToolbarActionState(
        actionType: .qrCode,
        iconName: StandardImageIdentifiers.Large.qrCode,
        isEnabled: true,
        a11yLabel: .QRCode.ToolbarButtonA11yLabel,
        a11yId: AccessibilityIdentifiers.Browser.ToolbarButtons.qrCode)

    lazy var cancelEditAction = ToolbarActionState(
        actionType: .cancelEdit,
        iconName: StandardImageIdentifiers.Large.chevronLeft,
        isEnabled: true,
        a11yLabel: AccessibilityIdentifiers.GeneralizedIdentifiers.back,
        a11yId: AccessibilityIdentifiers.Browser.UrlBar.cancelButton)

    lazy var menuAction = ToolbarActionState(
        actionType: .menu,
        iconName: StandardImageIdentifiers.Large.appMenu,
        isEnabled: true,
        a11yLabel: .AppMenu.Toolbar.MenuButtonAccessibilityLabel,
        a11yId: AccessibilityIdentifiers.Toolbar.settingsMenuButton)

    lazy var tabsAction = ToolbarActionState(
        actionType: .tabs,
        iconName: StandardImageIdentifiers.Large.tab,
        numberOfTabs: 1,
        isEnabled: true,
        a11yLabel: .TabsButtonShowTabsAccessibilityLabel,
        a11yId: AccessibilityIdentifiers.Toolbar.tabsButton)

    lazy var homeAction = ToolbarActionState(
        actionType: .home,
        iconName: StandardImageIdentifiers.Large.home,
        isEnabled: true,
        a11yLabel: .TabToolbarHomeAccessibilityLabel,
        a11yId: AccessibilityIdentifiers.Toolbar.homeButton)

    private func resolveGeneralBrowserMiddlewareActions(action: GeneralBrowserMiddlewareAction, state: AppState) {
        let uuid = action.windowUUID

        switch action.actionType {
        case GeneralBrowserMiddlewareActionType.browserDidLoad:
            guard let toolbarPosition = action.toolbarPosition else { return }

            let position = addressToolbarPositionFromSearchBarPosition(toolbarPosition)
            let addressToolbarModel = loadInitialAddressToolbarState(toolbarPosition: position)
            let navigationToolbarModel = loadInitialNavigationToolbarState(toolbarPosition: position)

            let action = ToolbarAction(addressToolbarModel: addressToolbarModel,
                                       navigationToolbarModel: navigationToolbarModel,
                                       toolbarPosition: position,
                                       windowUUID: uuid,
                                       actionType: ToolbarActionType.didLoadToolbars)
            store.dispatch(action)

        case GeneralBrowserMiddlewareActionType.websiteDidScroll:
            updateBorderPosition(action: action, state: state)

        case GeneralBrowserMiddlewareActionType.toolbarPositionChanged:
            updateToolbarPosition(action: action, state: state)

        default:
            break
        }
    }

    private func resolveToolbarMiddlewareActions(action: ToolbarMiddlewareAction, state: AppState) {
        switch action.actionType {
        case ToolbarMiddlewareActionType.didTapButton:
            resolveToolbarMiddlewareButtonTapActions(action: action, state: state)

        case ToolbarMiddlewareActionType.urlDidChange:
            guard let action = action as? ToolbarMiddlewareUrlChangeAction else { return }
            updateUrlAndActions(action: action, state: state)

        case ToolbarMiddlewareActionType.didStartEditingUrl:
            updateAddressToolbarNavigationActions(action: action, state: state, isEditing: true)

        case ToolbarMiddlewareActionType.cancelEdit:
            updateAddressToolbarNavigationActions(action: action, state: state, isEditing: false)

        default:
            break
        }
    }

    private func resolveToolbarMiddlewareButtonTapActions(action: ToolbarMiddlewareAction, state: AppState) {
        guard let buttonType = action.buttonType, let gestureType = action.gestureType else { return }

        let uuid = action.windowUUID
        switch gestureType {
        case .tap:
            handleToolbarButtonTapActions(action: action, state: state)
        case .longPress:
            handleToolbarButtonLongPressActions(actionType: buttonType, windowUUID: uuid)
        }
    }

    private func loadInitialAddressToolbarState(toolbarPosition: AddressToolbarPosition) -> AddressToolbarModel {
        let borderPosition = getAddressBorderPosition(toolbarPosition: toolbarPosition)

        return AddressToolbarModel(navigationActions: [ToolbarActionState](),
                                   pageActions: loadAddressToolbarPageElements(),
                                   browserActions: loadAddressToolbarBrowserElements(),
                                   borderPosition: borderPosition,
                                   url: nil)
    }

    private func loadAddressToolbarPageElements() -> [ToolbarActionState] {
        var pageActions = [ToolbarActionState]()
        pageActions.append(qrCodeScanAction)
        return pageActions
    }

    private func loadAddressToolbarBrowserElements() -> [ToolbarActionState] {
        var elements = [ToolbarActionState]()
        elements.append(tabsAction)
        elements.append(menuAction)
        return elements
    }

    private func loadInitialNavigationToolbarState(toolbarPosition: AddressToolbarPosition) -> NavigationToolbarModel {
        let actions = loadNavigationToolbarElements()
        let displayBorder = shouldDisplayNavigationToolbarBorder(toolbarPosition: toolbarPosition)
        return NavigationToolbarModel(actions: actions, displayBorder: displayBorder)
    }

    private func loadNavigationToolbarElements() -> [ToolbarActionState] {
        var elements = [ToolbarActionState]()
        elements.append(backAction(enabled: false))
        elements.append(forwardAction(enabled: false))
        elements.append(homeAction)
        elements.append(tabsAction)
        elements.append(menuAction)
        return elements
    }

    private func getAddressBorderPosition(toolbarPosition: AddressToolbarPosition,
                                          isPrivate: Bool = false,
                                          scrollY: CGFloat = 0) -> AddressToolbarBorderPosition? {
        return manager.getAddressBorderPosition(for: toolbarPosition, isPrivate: isPrivate, scrollY: scrollY)
    }

    private func shouldDisplayNavigationToolbarBorder(toolbarPosition: AddressToolbarPosition) -> Bool {
        return manager.shouldDisplayNavigationBorder(toolbarPosition: toolbarPosition)
    }

    private func handleToolbarButtonTapActions(action: ToolbarMiddlewareAction, state: AppState) {
        switch action.buttonType {
        case .home:
            let action = GeneralBrowserAction(windowUUID: action.windowUUID,
                                              actionType: GeneralBrowserActionType.goToHomepage)
            store.dispatch(action)
        case .qrCode:
            let action = GeneralBrowserAction(windowUUID: action.windowUUID,
                                              actionType: GeneralBrowserActionType.showQRcodeReader)
            store.dispatch(action)

        case .back:
            let action = GeneralBrowserAction(windowUUID: action.windowUUID,
                                              actionType: GeneralBrowserActionType.navigateBack)
            store.dispatch(action)

        case .forward:
            let action = GeneralBrowserAction(windowUUID: action.windowUUID,
                                              actionType: GeneralBrowserActionType.navigateForward)
            store.dispatch(action)

        case .tabs:
            let action = GeneralBrowserAction(windowUUID: action.windowUUID,
                                              actionType: GeneralBrowserActionType.showTabTray)
            store.dispatch(action)

        case .trackingProtection:
            let action = GeneralBrowserAction(windowUUID: action.windowUUID,
                                              actionType: GeneralBrowserActionType.showTrackingProtectionDetails)
            store.dispatch(action)

        case .menu:
            let action = GeneralBrowserAction(buttonTapped: action.buttonTapped,
                                              windowUUID: action.windowUUID,
                                              actionType: GeneralBrowserActionType.showMenu)
            store.dispatch(action)

        case .cancelEdit:
            updateAddressToolbarNavigationActions(action: action, state: state, isEditing: false)

        default:
            break
        }
    }

    private func handleToolbarButtonLongPressActions(actionType: ToolbarActionState.ActionType,
                                                     windowUUID: WindowUUID) {
        switch actionType {
        case .back, .forward:
            let action = GeneralBrowserAction(windowUUID: windowUUID,
                                              actionType: GeneralBrowserActionType.showBackForwardList)
            store.dispatch(action)
        case .tabs:
            let action = GeneralBrowserAction(windowUUID: windowUUID,
                                              actionType: GeneralBrowserActionType.showTabsLongPressActions)
            store.dispatch(action)
        default:
            break
        }
    }

    private func updateBorderPosition(action: GeneralBrowserMiddlewareAction, state: AppState) {
        guard let scrollOffset = action.scrollOffset,
              let toolbarState = state.screenState(ToolbarState.self,
                                                   for: .toolbar,
                                                   window: action.windowUUID)
        else { return }

        let addressToolbarState = toolbarState.addressToolbar
        let addressBorderPosition = getAddressBorderPosition(toolbarPosition: toolbarState.toolbarPosition,
                                                             isPrivate: toolbarState.isPrivateMode,
                                                             scrollY: scrollOffset.y)
        let displayNavToolbarBorder = shouldDisplayNavigationToolbarBorder(
            toolbarPosition: toolbarState.toolbarPosition)

        let needsAddressToolbarUpdate = addressToolbarState.borderPosition != addressBorderPosition
        let needsNavToolbarUpdate = toolbarState.navigationToolbar.displayBorder != displayNavToolbarBorder
        guard needsAddressToolbarUpdate || needsNavToolbarUpdate else { return }

        let addressToolbarModel = AddressToolbarModel(borderPosition: addressBorderPosition)
        let navToolbarModel = NavigationToolbarModel(displayBorder: displayNavToolbarBorder)

        let action = ToolbarAction(addressToolbarModel: addressToolbarModel,
                                   navigationToolbarModel: navToolbarModel,
                                   windowUUID: action.windowUUID,
                                   actionType: ToolbarActionType.scrollOffsetChanged)
        store.dispatch(action)
    }

    private func updateToolbarPosition(action: GeneralBrowserMiddlewareAction, state: AppState) {
        guard let toolbarPosition = action.toolbarPosition,
              let scrollOffset = action.scrollOffset,
              let toolbarState = state.screenState(ToolbarState.self,
                                                   for: .toolbar,
                                                   window: action.windowUUID)
        else { return }

        let position = addressToolbarPositionFromSearchBarPosition(toolbarPosition)

        let addressBorderPosition = getAddressBorderPosition(toolbarPosition: position,
                                                             isPrivate: toolbarState.isPrivateMode,
                                                             scrollY: scrollOffset.y)
        let displayNavToolbarBorder = shouldDisplayNavigationToolbarBorder(toolbarPosition: position)
        let addressToolbarModel = AddressToolbarModel(borderPosition: addressBorderPosition)
        let navToolbarModel = NavigationToolbarModel(displayBorder: displayNavToolbarBorder)

        let toolbarAction = ToolbarAction(addressToolbarModel: addressToolbarModel,
                                          navigationToolbarModel: navToolbarModel,
                                          toolbarPosition: position,
                                          windowUUID: action.windowUUID,
                                          actionType: ToolbarActionType.toolbarPositionChanged)
        store.dispatch(toolbarAction)
    }

    private func addressToolbarPositionFromSearchBarPosition(_ position: SearchBarPosition) -> AddressToolbarPosition {
        switch position {
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    // MARK: Address Toolbar Actions

    private func addressToolbarNavigationActions(
        action: ToolbarMiddlewareAction,
        state: AppState
    ) -> [ToolbarActionState] {
        var actions = [ToolbarActionState]()

        switch action.actionType {
        case ToolbarMiddlewareActionType.didStartEditingUrl,
            ToolbarMiddlewareActionType.cancelEdit:
            let navActions = addressToolbarNavigationDefaultActions(action: action, state: state)
            actions.append(contentsOf: navActions)

        case ToolbarMiddlewareActionType.urlDidChange:
            guard let action = action as? ToolbarMiddlewareUrlChangeAction else { return actions }
            let navActions = addressToolbarNavigationUrlChangeActions(action: action, state: state)
            actions.append(contentsOf: navActions)

        default:
            return actions
        }

        return actions
    }

    private func addressToolbarNavigationDefaultActions(
        action: ToolbarMiddlewareAction,
        state: AppState
    ) -> [ToolbarActionState] {
        var actions = [ToolbarActionState]()

        switch action.actionType {
        case ToolbarMiddlewareActionType.didStartEditingUrl:
            // back carrot when in edit mode
            actions.append(cancelEditAction)
            return actions

        default:
            return actions
        }
    }

    private func addressToolbarNavigationUrlChangeActions(
        action: ToolbarMiddlewareUrlChangeAction,
        state: AppState
    ) -> [ToolbarActionState] {
        var actions = [ToolbarActionState]()

        if action.isShowingNavigationToolbar || action.url == nil {
            // there are no navigation actions if on homepage or when nav toolbar is shown
            return actions
        } else if action.url != nil {
            // back/forward when url exists and nav toolbar is not shown
            let isBackButtonEnabled = action.canGoBack
            let isForwardButtonEnabled = action.canGoForward
            actions.append(backAction(enabled: isBackButtonEnabled))
            actions.append(forwardAction(enabled: isForwardButtonEnabled))
        }
        return actions
    }

    private func addressToolbarPageActions(
        action: ToolbarMiddlewareAction,
        state: AppState
    ) -> [ToolbarActionState] {
        var actions = [ToolbarActionState]()

        guard let toolbarState = state.screenState(ToolbarState.self,
                                                   for: .toolbar,
                                                   window: action.windowUUID)
        else { return actions }

        var url = toolbarState.addressToolbar.url
        if let action = action as? ToolbarMiddlewareUrlChangeAction {
            url = action.url
        }

        guard let url else {
            // On homepage we only show the QR code button
            actions.append(qrCodeScanAction)
            return actions
        }

        var isLoading = false

        // share, reload if url exists + potentially reader mode & fakespot
        switch action.actionType {
        case ToolbarMiddlewareActionType.websiteLoadingStateDidChange:
            if action.isLoading == true {
                actions.append(stopLoadingAction)
            } else if action.isLoading == false {
                actions.append(reloadAction)
            }
        default:
            return actions
        }

        return actions
    }

    private func updateUrlAndActions(action: ToolbarMiddlewareUrlChangeAction,
                                     state: AppState) {
        guard let addressToolbarModel = generateAddressToolbarNavigationActions(action: action,
                                                                                state: state,
                                                                                url: action.url,
                                                                                isEditing: false)
        else { return }

        let toolbarAction = ToolbarAction(addressToolbarModel: addressToolbarModel,
                                          url: action.url,
                                          windowUUID: action.windowUUID,
                                          actionType: ToolbarActionType.urlDidChange)
        store.dispatch(toolbarAction)
    }

    private func updateAddressToolbarNavigationActions(action: ToolbarMiddlewareAction,
                                                       state: AppState,
                                                       isEditing: Bool) {
        guard let addressToolbarModel = generateAddressToolbarNavigationActions(action: action,
                                                                                state: state,
                                                                                isEditing: isEditing)
        else { return }

        let toolbarAction = ToolbarAction(addressToolbarModel: addressToolbarModel,
                                          windowUUID: action.windowUUID,
                                          actionType: ToolbarActionType.addressToolbarActionsDidChange)
        store.dispatch(toolbarAction)
    }

    private func generateAddressToolbarNavigationActions(
        action: ToolbarMiddlewareAction,
        state: AppState,
        url: URL? = nil,
        isEditing: Bool? = nil) -> AddressToolbarModel? {
        guard let toolbarState = state.screenState(ToolbarState.self, for: .toolbar, window: action.windowUUID)
        else { return nil }

        let navigationActions = addressToolbarNavigationActions(action: action, state: state)
        let addressToolbarModel = AddressToolbarModel(
            navigationActions: navigationActions,
            pageActions: toolbarState.addressToolbar.pageActions,
            browserActions: toolbarState.addressToolbar.browserActions,
            borderPosition: toolbarState.addressToolbar.borderPosition,
            url: url ?? toolbarState.addressToolbar.url,
            isEditing: isEditing)
        return addressToolbarModel
    }

    private func backAction(enabled: Bool) {
        return ToolbarActionState(
            actionType: .back,
            iconName: StandardImageIdentifiers.Large.back,
            isEnabled: enabled,
            a11yLabel: .TabToolbarBackAccessibilityLabel,
            a11yId: AccessibilityIdentifiers.Toolbar.backButton)
    }

    private func forwardAction(enabled: Bool) {
        return ToolbarActionState(
            actionType: .forward,
            iconName: StandardImageIdentifiers.Large.forward,
            isEnabled: enabled,
            a11yLabel: .TabToolbarForwardAccessibilityLabel,
            a11yId: AccessibilityIdentifiers.Toolbar.forwardButton)
    }
}

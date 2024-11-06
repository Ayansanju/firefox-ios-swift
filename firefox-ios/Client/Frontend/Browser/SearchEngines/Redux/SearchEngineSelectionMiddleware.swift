// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import ToolbarKit

final class SearchEngineSelectionMiddleware {
    private let profile: Profile
    private let logger: Logger
    private let searchEnginesManager: SearchEnginesManager

    init(profile: Profile = AppContainer.shared.resolve(),
         searchEnginesManager: SearchEnginesManager? = nil,
         logger: Logger = DefaultLogger.shared) {
        self.profile = profile
        self.logger = logger
        self.searchEnginesManager = searchEnginesManager ?? SearchEnginesManager(prefs: profile.prefs, files: profile.files)
    }

    lazy var searchEngineSelectionProvider: Middleware<AppState> = { [self] state, action in
        switch action.actionType {
        case SearchEngineSelectionActionType.viewDidLoad:
            guard let action = action as? SearchEngineSelectionAction else { return }

            guard let searchEngines = searchEnginesManager.orderedEngines, !searchEngines.isEmpty else {
                // The SearchEngineManager should have loaded these by now, but if not, attempt to fetch the search engines
                self.searchEnginesManager.getOrderedEngines { [weak self] searchEngines in
                    self?.notifyDidLoad(windowUUID: action.windowUUID, searchEngines: searchEngines)
                }
                return
            }

            notifyDidLoad(windowUUID: action.windowUUID, searchEngines: searchEngines)

        case SearchEngineSelectionActionType.didTapSearchEngine:
            guard let action = action as? SearchEngineSelectionAction else { return }

            let didSelectAction = SearchEngineSelectionAction(
                windowUUID: action.windowUUID,
                actionType: SearchEngineSelectionMiddlewareActionType.didSelectAlternativeSearchEngine
            )
            store.dispatch(didSelectAction)

        case ToolbarActionType.cancelEdit:
            guard let action = action as? ToolbarAction else { return }

            let didClearAction = SearchEngineSelectionAction(
                windowUUID: action.windowUUID,
                actionType: SearchEngineSelectionMiddlewareActionType.didClearAlternativeSearchEngine
            )
            store.dispatch(didClearAction)

        default:
            break
        }
    }

    private func notifyDidLoad(windowUUID: WindowUUID, searchEngines: [OpenSearchEngine]) {
        let action = SearchEngineSelectionAction(
            windowUUID: windowUUID,
            actionType: SearchEngineSelectionActionType.didLoadSearchEngines,
            searchEngines: searchEngines
        )
        store.dispatch(action)
    }
}

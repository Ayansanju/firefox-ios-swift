// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux

class TabsPanelMiddleware {
    var tabs = [TabCellModel]()
    var inactiveTabs = [String]()
    var selectedPanel: TabTrayPanelType = .tabs

    init() {}

    lazy var tabsPanelProvider: Middleware<AppState> = { state, action in
        switch action {
        case TabTrayAction.tabTrayDidLoad(let panelType):
            let tabTray = self.getTabTrayState(for: panelType)
            store.dispatch(TabTrayAction.didLoadTabTray(tabTray))
        case TabPanelAction.tabPanelDidLoad(let isPrivate):
            let tabState = self.getTabsState(for: isPrivate)
            store.dispatch(TabPanelAction.didLoadTabPanel(tabState))
        case TabPanelAction.addNewTab(let isPrivate):
            self.addNewTab()
            store.dispatch(TabPanelAction.refreshTab(self.tabs))
        case TabPanelAction.moveTab(let originIndex, let destinationIndex):
            self.moveTab(from: originIndex, to: destinationIndex)
            store.dispatch(TabPanelAction.refreshTab(self.tabs))
        case TabPanelAction.closeTab(let index):
            self.closeTab(for: index)
            store.dispatch(TabPanelAction.refreshTab(self.tabs))
        case TabPanelAction.closeAllTabs:
            self.closeAllTabs()
            store.dispatch(TabPanelAction.refreshTab(self.tabs))
        default:
            break
        }
    }

    func getTabTrayState(for panelType: TabTrayPanelType) -> TabTrayState {
        selectedPanel = panelType
        guard panelType != .syncedTabs else { return TabTrayState() }

        let isPrivate = panelType == .privateTabs
        return TabTrayState(isPrivateMode: isPrivate,
                            selectedPanel: panelType,
                            normalTabsCount: "\(tabs.count)")
    }

    func getTabsState(for isPrivate: Bool) -> TabsState {
        resetMock()
        for index in 0...2 {
            let cellState = TabCellModel.emptyTabState(title: "Tab \(index)")
            tabs.append(cellState)
        }
        inactiveTabs =  !isPrivate ? ["Tab1", "Tab2", "Tab3"] : [String]()
        let isInactiveTabsExpanded = !isPrivate && !inactiveTabs.isEmpty

        return TabsState(isPrivateMode: isPrivate,
                         tabs: tabs,
                         inactiveTabs: inactiveTabs,
                         isInactiveTabsExpanded: isInactiveTabsExpanded)
    }

    private func addNewTab() {
        let cellState = TabCellModel.emptyTabState(title: "New tab")
        tabs.append(cellState)
    }

    private func moveTab(from originIndex: Int, to destinationIndex: Int) {
        tabs.move(fromOffsets: IndexSet(integer: originIndex), toOffset: destinationIndex)
    }

    private func closeTab(for index: Int) {
        tabs.remove(at: index)
    }

    private func closeAllTabs() {
        tabs.removeAll()
    }

    private func resetMock() {
        // Clean up array before getting the new panel
        tabs.removeAll()
        inactiveTabs.removeAll()
    }
}

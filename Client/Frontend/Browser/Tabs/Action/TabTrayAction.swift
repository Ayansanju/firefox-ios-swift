// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux

enum TabTrayAction: Action {
    case tabTrayDidLoad(TabTrayPanelType)
    case changePanel(TabTrayPanelType)

    // Middleware actions
    case didLoadTabTray(TabTrayState)
}

enum TabPanelAction: Action {
    case tabPanelDidLoad(TabTrayPanelType)
    case addNewTab(Bool)
    case closeTab(Int)
    case closeAllTabs
    case moveTab(Int, Int)
    case toggleInactiveTabs(Bool)
    case closeInactiveTabs(Int)
    case closeAllInactiveTabs
    case learnMorePrivateMode

    // Middleware actions
    case didLoadTabPanel(TabsState)
    // Response to all user actions involving tabs ex: add, close and close all tabs
    case refreshTab([TabCellModel])
    case inactiveTabsChanged
}

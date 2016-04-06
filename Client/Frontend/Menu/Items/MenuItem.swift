/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

protocol MenuItem {
    var title: String { get }
    var action: Action? { get }
    func iconForState(appState: AppState) -> UIImage?
}

struct FirefoxMenuItem: MenuItem {
    let title: String
    let action: Action?
    private let iconName: String
    private let privateModeIconName: String

    private var icon: UIImage? {
        return UIImage(named: iconName)
    }

    private var privateModeIcon: UIImage? {
        return UIImage(named: privateModeIconName)
    }

    func iconForState(appState: AppState) -> UIImage?  {
        return appState.isPrivate() ? privateModeIcon : icon
    }

    init(title: String, action: Action? = nil, icon: String, privateModeIcon: String) {
        self.title = title
        self.iconName = icon
        self.privateModeIconName = privateModeIcon
        self.action = action
    }
}

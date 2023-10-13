// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

public protocol PrivateModeUI {
    func applyUIMode(isPrivate: Bool, theme: Theme)
}

// Used to pass in a theme to a view or cell to apply a theme
public protocol ThemeApplicable {
    func applyTheme(theme: Theme)
}

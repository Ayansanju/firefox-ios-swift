// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

// Manages different types of onboarding that gets shown at the launch of the application
class LaunchCoordinator: BaseCoordinator {
    private let launchScreenManager: LaunchScreenManager

    init(router: Router,
         launchScreenManager: LaunchScreenManager) {
        self.launchScreenManager = launchScreenManager
        super.init(router: router)
    }

    func start(with launchType: LaunchType, onCompletion: @escaping () -> Void) {
        // FXIOS-5989: Handle different onboarding types
        switch launchType {
        case .intro:
            break
        case .update:
            break
        case .defaultBrowser:
            break
        case .survey:
            break
        }
    }
}

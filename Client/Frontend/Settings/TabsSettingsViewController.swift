/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

class TabsSettingsViewController: SettingsTableViewController {

    init() {
        super.init(style: .grouped)

        self.title = .SettingsCustomizeTabsTitle
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func generateSettings() -> [SettingSection] {

        var sectionItems = [Setting]()


        let inactiveTabsSetting = BoolSetting(with: .inactiveTabs,
                                              titleText: NSAttributedString(string: .SettingsCustomizeTabsInactiveTabs))

        let tabGroupsSetting = BoolSetting(with: .groupedTabs,
                                           titleText: NSAttributedString(string: .SettingsCustomizeTabsTabGroups))


        sectionItems.append(inactiveTabsSetting)
        sectionItems.append(tabGroupsSetting)

        return [SettingSection(title: NSAttributedString(string: .SettingsCustomizeTabsSectionTitle),
                               children: sectionItems)]
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.keyboardDismissMode = .onDrag
    }
}

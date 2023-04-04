// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Shared

/// Data source for handling LoginData objects from a Cursor
class LoginDataSource: NSObject, UITableViewDataSource {
    // in case there are no items to run cellForRowAt on, use an empty state view
    private let emptyStateView = NoLoginsView()
    var viewModel: LoginListViewModel

    let boolSettings: (BoolSetting, BoolSetting)

    init(viewModel: LoginListViewModel) {
        self.viewModel = viewModel
        boolSettings = (
            BoolSetting(prefs: viewModel.profile.prefs,
                        prefKey: PrefsKeys.LoginsSaveEnabled,
                        defaultValue: true,
                        attributedTitleText: NSAttributedString(string: .Settings.Passwords.SavePasswords)),
            BoolSetting(prefs: viewModel.profile.prefs,
                        prefKey: PrefsKeys.LoginsShowShortcutMenuItem,
                        defaultValue: true,
                        attributedTitleText: NSAttributedString(string: .SettingToShowLoginsInAppMenu)))
        super.init()
    }

    @objc
    func numberOfSections(in tableView: UITableView) -> Int {
        if viewModel.loginRecordSections.isEmpty {
            tableView.backgroundView = emptyStateView
            return 1
        }

        tableView.backgroundView = nil
        // Add one section for the settings section.
        return viewModel.loginRecordSections.count + 1
    }

    @objc
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == LoginListViewController.loginsSettingsSection {
            return 2
        }
        return viewModel.loginsForSection(section)?.count ?? 0
    }

    @objc
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == LoginListViewController.loginsSettingsSection,
           let cell = tableView.dequeueReusableCell(withIdentifier: LoginListTableViewSettingsCell.cellIdentifier,
                                                    for: indexPath) as? LoginListTableViewSettingsCell {
            let hideSettings = viewModel.searchController?.isActive ?? false || tableView.isEditing
            let setting = indexPath.row == 0 ? boolSettings.0 : boolSettings.1
            setting.onConfigureCell(cell, theme: viewModel.theme)
            if hideSettings {
                cell.isHidden = true
            } else if viewModel.isDuringSearchControllerDismiss {
                // Fade in the cell while dismissing the search or the cell showing suddenly looks janky
                cell.isHidden = false
                cell.contentView.alpha = 0
                cell.accessoryView?.alpha = 0
                UIView.animate(withDuration: 0.6) {
                    cell.contentView.alpha = 1
                    cell.accessoryView?.alpha = 1
                }
            }
            return cell
        } else if let cell = tableView.dequeueReusableCell(withIdentifier: LoginListTableViewCell.cellIdentifier,
                                                           for: indexPath) as? LoginListTableViewCell {
            guard let login = viewModel.loginAtIndexPath(indexPath) else { return cell }
            let username = login.decryptedUsername
            cell.hostnameLabel.text = login.hostname
            cell.usernameLabel.text = username.isEmpty ? "(no username)" : username
            // TODO: FXIOS-4995 - BreachAlertsManager theming
            if NightModeHelper.hasEnabledDarkTheme() {
                cell.breachAlertImageView.tintColor = BreachAlertsManager.darkMode
            } else {
                cell.breachAlertImageView.tintColor = BreachAlertsManager.lightMode
            }
            if let breaches = viewModel.userBreaches, breaches.contains(login) {
                cell.breachAlertImageView.isHidden = false
            }
            cell.applyTheme(theme: viewModel.theme)
            cell.configure(inset: tableView.separatorInset)
            return cell
        }

        return UITableViewCell()
    }
}

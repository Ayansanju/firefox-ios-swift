// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import WebKit

/// The settings page
class SettingsViewController: UIViewController, UITableViewDelegate {
    private var tableView: UITableView
    private var dataSource = SettingsDataSource()

    private lazy var titleLabel: UILabel = .build { label in
        label.font = UIFont.systemFont(ofSize: 30, weight: UIFont.Weight.medium)
        label.text = "Settings"
        label.textAlignment = .center
    }

    init() {
        self.tableView = UITableView(frame: .zero, style: .grouped)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        configureTitle()
        tableView.reloadData()
        view.backgroundColor = tableView.backgroundColor
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.isScrollEnabled = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        tableView.tableHeaderView = UIView(frame: CGRect(origin: .zero,
                                                         size: CGSize(width: 0, height: CGFloat.leastNormalMagnitude)))
        tableView.dataSource = dataSource
        tableView.delegate = self
        tableView.register(SettingsCell.self, forCellReuseIdentifier: SettingsCell.identifier)
    }

    private func configureTitle() {
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: tableView.topAnchor, constant: -16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let model: SettingsCellViewModel = dataSource.models[indexPath.row]
        let settingType = model.settingType

        switch settingType {
        case .findInPage:
            break // TODO: FXIOS-8087 - Handle find in page in WebEngine
        }
    }
}

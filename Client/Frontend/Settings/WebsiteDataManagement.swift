/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import WebKit

private let SectionSites = 0
private let SectionShowMore = 1
private let SectionButton = 2
private let NumberOfSections = 3
private let SectionHeaderFooterIdentifier = "SectionHeaderFooterIdentifier"


class WebsiteDataManagement: UITableViewController {
    fileprivate var clearButton: UITableViewCell?
    fileprivate var showMoreButton: UITableViewCell?
    var searchResults: UITableViewController!
    var searchController: UISearchController!
    var showMoreButtonEnabled = true

    private var filteredSiteRecords = [siteData]()
    private var siteRecords = [siteData]()

    fileprivate typealias DefaultCheckedState = Bool

    let dataStore = WKWebsiteDataStore.default()
    let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

    let flexible = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.flexibleSpace, target: self, action: nil)
    let editButton: UIBarButtonItem = UIBarButtonItem(title: "edit", style: .plain, target: self, action: #selector(didPressEdit))
    let doneButton: UIBarButtonItem = UIBarButtonItem(title: "done", style:.plain, target: self, action: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Strings.SettingsWebsiteDataTitle

        //toolbar setup
        self.tableView.allowsMultipleSelectionDuringEditing = true
        self.navigationController?.setToolbarHidden(false, animated: false)


        //self.navigationController?.toolbar.barTintColor = UIColor.white
        self.navigationItem.rightBarButtonItem = self.editButtonItem

        //get websites
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { (records) in
            for record in records {
                self.siteRecords.append(siteData(dataOfSite: record, nameOfSite: record.displayName))
            }
            self.siteRecords.sort { $0.nameOfSite < $1.nameOfSite }
            if self.siteRecords.count >= 5 {
                self.siteRecords.removeLast(self.siteRecords.count - 5)
            } else {
                self.showMoreButtonEnabled = false
            }
            self.tableView.reloadData()
        }

        // Setup the Search Controller
        let searchResults = websiteSearchResults(data: self.siteRecords)
        searchController = UISearchController(searchResultsController: searchResults)
        searchController.searchResultsUpdater = searchResults
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Filter Sites"
        if #available(iOS 11.0, *) {
            navigationItem.searchController = searchController
        } else {
            // Fallback on earlier versions
        }
        definesPresentationContext = true

        tableView.register(ThemedTableSectionHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderFooterIdentifier)

        tableView.separatorColor = UIColor.theme.tableView.separator
        tableView.backgroundColor = UIColor.theme.tableView.headerBackground
        let footer = ThemedTableSectionHeaderFooterView(frame: CGRect(width: tableView.bounds.width, height: SettingsUX.TableViewHeaderFooterHeight))
        footer.showBottomBorder = false
        tableView.tableFooterView = footer

        //edit feature
        self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)

        if indexPath.section == SectionSites {
            assert(indexPath.section == SectionSites)
            if isFiltering() {
                let site = filteredSiteRecords[indexPath.item]
                cell.textLabel?.text = site.nameOfSite
            } else {
                let site = siteRecords[indexPath.item]
                cell.textLabel?.text = site.nameOfSite
            }

        } else if indexPath.section == SectionShowMore {
            assert(indexPath.section == SectionShowMore)
            cell.textLabel?.text = "Show More"
            cell.textLabel?.textColor = showMoreButtonEnabled ? UIColor.theme.general.highlightBlue : UIColor.gray
            cell.accessibilityTraits = UIAccessibilityTraitButton
            cell.accessibilityIdentifier = "ShowMoreWebsiteData"
            showMoreButton = cell

        } else {
            assert(indexPath.section == SectionButton)
            cell.textLabel?.text = Strings.SettingsClearAllWebsiteDataButton
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = UIColor.theme.general.destructiveRed
            cell.accessibilityTraits = UIAccessibilityTraitButton
            cell.accessibilityIdentifier = "ClearAllWebsiteData"
            clearButton = cell
        }
        return cell
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return NumberOfSections
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == SectionSites {
            if isFiltering() {
                return filteredSiteRecords.count
            }
            return siteRecords.count
        } else if section == SectionShowMore {
            return 1
        }
        assert(section == SectionButton)
        return 1
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        if (indexPath.section == SectionShowMore && showMoreButtonEnabled) || indexPath.section == SectionButton || (indexPath.section == SectionSites && self.tableView.isEditing) {
            return true
        }
        return false
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == SectionShowMore {
            //get websites
            self.siteRecords.removeAll()
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { (records) in
                for record in records {
                        self.siteRecords.append(siteData(dataOfSite: record, nameOfSite: record.displayName))
                }
                self.siteRecords.sort { $0.nameOfSite < $1.nameOfSite }
                self.showMoreButtonEnabled = false
                self.tableView.reloadData()
            }
        }
        guard indexPath.section == SectionButton else { return }
        if indexPath.section == SectionButton {
            func clearwebsitedata(_ action: UIAlertAction) {
                WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: .distantPast, completionHandler: {})
                siteRecords.removeAll()
                showMoreButtonEnabled = false
                tableView.reloadData()
            }
            let alert =  UIAlertController.clearWebsiteDataAlert(okayCallback: clearwebsitedata)
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            self.present(alert, animated: true, completion: nil)
        }
        tableView.deselectRow(at: indexPath, animated: false)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard indexPath.section == SectionSites else { return false }
        return true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == UITableViewCellEditingStyle.delete) {
            dataStore.removeData(ofTypes: dataTypes, for: [siteRecords[indexPath.item].dataOfSite], completionHandler: { return })
            siteRecords.remove(at: indexPath.item)
            tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderFooterIdentifier) as! ThemedTableSectionHeaderFooterView
        var sectionTitle: String?
        if section == SectionSites {
            sectionTitle = NSLocalizedString("WEBSITE DATA", comment: "Title for website data section.")
        } else {
            sectionTitle = nil
        }
        headerView.titleLabel.text = sectionTitle
        return headerView
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section != SectionShowMore {
            return SettingsUX.TableViewHeaderFooterHeight
        }
        return 0
    }

    func searchBarIsEmpty() -> Bool {
        // Returns true if the text is empty or nil
        return searchController.searchBar.text?.isEmpty ?? true
    }

    func filterContentForSearchText(_ searchText: String) {
        filteredSiteRecords = siteRecords.filter({( siteRecord : siteData) -> Bool in
            return siteRecord.nameOfSite.lowercased().contains(searchText.lowercased())
        })
        tableView.reloadData()
    }

    func isFiltering() -> Bool {
        return searchController.isActive && !searchBarIsEmpty()
    }

    @objc func didPressEdit() {
        self.tableView.setEditing(true, animated: true)
    }
}

class websiteSearchResults: UITableViewController {
    private var filteredSiteRecords = [siteData]()
    private var siteRecords : [siteData]
    let test = ["1", "2", "3"]
    init(data:[siteData]) {
        self.siteRecords = data
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredSiteRecords.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let site = filteredSiteRecords[indexPath.item]
        cell.textLabel?.text = site.nameOfSite
        return cell
    }

    func filterContentForSearchText(_ searchText: String) {
        filteredSiteRecords = siteRecords.filter({( siteRecord : siteData) -> Bool in
            return siteRecord.nameOfSite.lowercased().contains(searchText.lowercased())
        })
        tableView.reloadData()
    }

    @objc func didPressEdit() {
        self.tableView.setEditing(true, animated: true)
    }
}

extension websiteSearchResults: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
    }
}



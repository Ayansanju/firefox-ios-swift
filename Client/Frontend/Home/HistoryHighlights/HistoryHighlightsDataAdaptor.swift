// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

protocol HistoryHighlightsDataAdaptor {
    var delegate: HistoryHighlightsDelegate? { get set }

    func getHistoryHightlights() -> [HighlightItem]
    func delete(_ item: HighlightItem)
}

protocol HistoryHighlightsDelegate: AnyObject {
    func didLoadNewData()
}

class HistoryHighlightsDataAdaptorImplementation: HistoryHighlightsDataAdaptor {

    private var historyItems = [HighlightItem]()
    private var historyManager: HistoryHighlightsManagerProtocol
    private var profile: Profile
    private var tabManager: TabManagerProtocol
    private var deletionUtility: HistoryDeletionUtility
    var notificationCenter: NotificationProtocol
    weak var delegate: HistoryHighlightsDelegate?

    init(historyManager: HistoryHighlightsManagerProtocol = HistoryHighlightsManager(),
         profile: Profile,
         tabManager: TabManagerProtocol,
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.historyManager = historyManager
        self.profile = profile
        self.tabManager = tabManager
        self.notificationCenter = notificationCenter
        self.deletionUtility = HistoryDeletionUtility(with: profile)

        setupNotifications(forObserver: self,
                           observing: [.HistoryUpdated])
        loadHistory()
    }

    func getHistoryHightlights() -> [HighlightItem] {
        return historyItems
    }

    func delete(_ item: HighlightItem) {
        let urls = extractDeletableURLs(from: item)

        deletionUtility.delete(urls) { [weak self] success in
            if success {
                self?.loadHistory()
            }
        }
    }

    // MARK: - Private Methods

    private func loadHistory() {
        historyManager.getHighlightsData(
            with: profile,
            and: tabManager.tabs,
            shouldGroupHighlights: true) { [weak self] highlights in

                self?.historyItems = highlights ?? []
                self?.delegate?.didLoadNewData()
        }
    }

    private func extractDeletableURLs(from item: HighlightItem) -> [String] {
        var urls = [String]()
        if item.type == .item, let url = item.siteUrl?.absoluteString {
            urls = [url]

        } else if item.type == .group, let items = item.group {
            items.forEach { groupedItem in
                if let url = groupedItem.siteUrl?.absoluteString { urls.append(url) }
            }
        }

        return urls
    }
}

extension HistoryHighlightsDataAdaptorImplementation: Notifiable {
    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case .HistoryUpdated:
            loadHistory()
        default:
            return
        }
    }
}

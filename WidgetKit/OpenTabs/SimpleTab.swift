/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

let userDefaultsKey = "myTabKey1"
let userDefaults = UserDefaults(suiteName: AppInfo.sharedContainerIdentifier)!

struct SimpleTab: Hashable, Codable {
    var title: String?
    var url: URL?
    let lastUsedTime: Timestamp? // From Session Data
    var faviconURL: String?
    var uuid: String = ""
    var isPrivate: Bool = false
}

extension SimpleTab {
    static func compareTemp(dict: [String: SimpleTab]?, tab: SavedTab) -> Bool {
        // case: nothing is saved
        guard dict != nil else {
            return false
        }
        
        // case: dict is available lets check if it has a tab
        for (_,v) in dict! {
            if tab.sessionData?.lastUsedTime == v.lastUsedTime && tab.url == v.url {
                return true
            }
        }
        return false
    }
    
    static func getSimpleTabDict() -> [String: SimpleTab]? {
        if let tbs = userDefaults.object(forKey: userDefaultsKey) as? Data {
            do {
                // Decode data to object
                let jsonDecoder = JSONDecoder()
                let tabs = try jsonDecoder.decode([String: SimpleTab].self, from: tbs)
                tabs.forEach {
                    print("key - \($0)\nValue - \($1)\n")
                }
                return tabs
            }
            catch {
                print("Error occured")
            }
        }
        return nil
    }
    
    static func saveSimpleTab(tabs:[String: SimpleTab]?) {
        guard let tabs = tabs, !tabs.isEmpty else {
            userDefaults.removeObject(forKey: userDefaultsKey)
            return
        }
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(tabs) {
            userDefaults.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    static func convertedTabs(_ tabs: [SavedTab]) -> ([SimpleTab], [String: SimpleTab]) {
        var simpleTabs: [String: SimpleTab] = [:]
        for tab in tabs {
            var url:URL?
            // Set URL
            // Check if we have any url
            if tab.url != nil {
                url = tab.url
            // Check if session data urls have something
            } else if tab.sessionData?.urls != nil {
                url = tab.sessionData?.urls.last
            }
            
            // Ignore internal about urls which corresponds to Home
            if url != nil, url!.absoluteString.starts(with: "internal://local/about/") {
                continue
            }
            
            // Set Title
            var title = tab.title ?? ""
            // There is no title then use the base url
            if title.isEmpty {
                title = url?.shortDisplayString ?? ""
            }
            
            // An id for simple tab
            let tempud = String(tab.sessionData?.lastUsedTime ?? 0)
            let uuid = UUID().uuidString
            let value = SimpleTab(title: title, url: url, lastUsedTime: tab.sessionData?.lastUsedTime ?? 0, faviconURL: tab.faviconURL, uuid: tempud, isPrivate: tab.isPrivate)
            simpleTabs[tempud] = value
        }

        let arrayFromDic = Array(simpleTabs.values.map{ $0 })
        return (arrayFromDic, simpleTabs)
    }
}



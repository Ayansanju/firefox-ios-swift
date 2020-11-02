/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Sentry
import Shared

struct SiteArchiver {
    static func tabsToRestore(tabsStateArchivePath: String?) -> ([SavedTab], [SimpleTab]) {
        guard let tabStateArchivePath = tabsStateArchivePath,
              FileManager.default.fileExists(atPath: tabStateArchivePath),
              let tabData = try? Data(contentsOf: URL(fileURLWithPath: tabStateArchivePath)) else {
            return ([SavedTab](), [SimpleTab]())
        }
        
        let unarchiver = NSKeyedUnarchiver(forReadingWith: tabData)
        unarchiver.setClass(SavedTab.self, forClassName: "Client.SavedTab")
        unarchiver.setClass(SessionData.self, forClassName: "Client.SessionData")
        
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        guard let tabs = unarchiver.decodeObject(forKey: "tabs") as? [SavedTab] else {
            Sentry.shared.send(
                message: "Failed to restore tabs",
                tag: SentryTag.tabManager,
                severity: .error,
                description: "\(unarchiver.error ??? "nil")")
            SimpleTab.saveSimpleTab(tabs: nil)
            return ([SavedTab](), [SimpleTab]())
        }
        
        let simpleTabs = SimpleTab.convertedTabs(tabs)
        SimpleTab.saveSimpleTab(tabs: simpleTabs.1)
        return (tabs, simpleTabs.0)
    }
}

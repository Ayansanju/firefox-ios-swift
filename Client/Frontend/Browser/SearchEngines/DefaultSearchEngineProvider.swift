// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Shared

protocol SearchEngineProvider {
    func getOrderedEngines(customEngines: [OpenSearchEngine],
                           orderedEngineNames: [String]?,
                           completion: @escaping ([OpenSearchEngine]) -> Void)
    func getUnorderedBundledEnginesFor(locale: Locale,
                                       possibleLanguageIdentifier: [String],
                                       completion: @escaping ([OpenSearchEngine]) -> Void)
}

class DefaultSearchEngineProvider: SearchEngineProvider {
    private let orderedEngineNames = "search.orderedEngineNames"

    func getOrderedEngines(customEngines: [OpenSearchEngine],
                           orderedEngineNames: [String]?,
                           completion: @escaping ([OpenSearchEngine]) -> Void) {
        let locale = Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
        getUnorderedBundledEnginesFor(locale: locale,
                                      possibleLanguageIdentifier: locale.possibilitiesForLanguageIdentifier(),
                                      completion: { [weak self] engineResults in
            let unorderedEngines = customEngines + engineResults

            // might not work to change the default.
            guard let orderedEngineNames = orderedEngineNames else {
                // We haven't persisted the engine order, so return whatever order we got from disk.

                DispatchQueue.main.async {
                    completion(unorderedEngines)
                }

                return
            }

            // We have a persisted order of engines, so try to use that order.
            // We may have found engines that weren't persisted in the ordered list
            // (if the user changed locales or added a new engine); these engines
            // will be appended to the end of the list.
            let orderedEngines = unorderedEngines.sorted { engine1, engine2 in
                let index1 = orderedEngineNames.firstIndex(of: engine1.shortName)
                let index2 = orderedEngineNames.firstIndex(of: engine2.shortName)

                if index1 == nil && index2 == nil {
                    return engine1.shortName < engine2.shortName
                }

                // nil < N for all non-nil values of N.
                if index1 == nil || index2 == nil {
                    return index1 ?? -1 > index2 ?? -1
                }

                return index1! < index2!
            }

            DispatchQueue.main.async {
                completion(orderedEngines)
            }
        })
    }

    func getUnorderedBundledEnginesFor(locale: Locale,
                                       possibleLanguageIdentifier: [String],
                                       completion: @escaping ([OpenSearchEngine]) -> Void ) {
        let region = locale.regionCode ?? "US"
        let parser = OpenSearchParser(pluginMode: true)

        guard let pluginDirectory = Bundle.main.resourceURL?.appendingPathComponent("SearchPlugins") else {
            assertionFailure("Search plugins not found. Check bundle")
            completion([])
            return
        }

        guard let defaultSearchPrefs = DefaultSearchPrefs(with: pluginDirectory.appendingPathComponent("list.json")) else {
            assertionFailure("Failed to parse List.json")
            completion([])
            return
        }
        let possibilities = possibleLanguageIdentifier
        let engineNames = defaultSearchPrefs.visibleDefaultEngines(for: possibilities, and: region)
        let defaultEngineName = defaultSearchPrefs.searchDefault(for: possibilities, and: region)
        assert(!engineNames.isEmpty, "No search engines")

        DispatchQueue.global().async {
            let result = engineNames.map({ (name: $0, path: pluginDirectory.appendingPathComponent("\($0).xml").path) })
                .filter({
                    FileManager.default.fileExists(atPath: $0.path)
                }).compactMap({
                    parser.parse($0.path, engineID: $0.name)
                }).sorted { e, _ in
                    e.shortName == defaultEngineName
                }

            completion(result)
        }
    }
}

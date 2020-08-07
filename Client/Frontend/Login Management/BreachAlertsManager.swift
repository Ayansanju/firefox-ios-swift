/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Storage // or whichever module has the LoginsRecord class
import Shared // or whichever module has the Maybe class

/// Breach structure decoded from JSON
struct BreachRecord: Codable, Equatable, Hashable {
    var name: String
    var title: String
    var domain: String
    var breachDate: String
    var description: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case title = "Title"
        case domain = "Domain"
        case breachDate = "BreachDate"
        case description = "Description"
    }
}

/// A manager for the user's breached login information, if any.
final public class BreachAlertsManager {
    static let icon = UIImage(named: "Breached Website")?.withRenderingMode(.alwaysTemplate)
    static let listColor = UIColor(red: 0.78, green: 0.16, blue: 0.18, alpha: 1.00)
    static let detailColor = UIColor(red: 0.59, green: 0.11, blue: 0.11, alpha: 1.00)
    static let monitorAboutUrl = URL(string: "https://monitor.firefox.com/about")
    var breaches = Set<BreachRecord>()
    var client: BreachAlertsClientProtocol
    var profile: Profile!
    private lazy var cacheURL: URL = {
        return URL(fileURLWithPath: (try? self.profile.files.getAndEnsureDirectory())!, isDirectory: true).appendingPathComponent("breaches.json")
    }()
    init(_ client: BreachAlertsClientProtocol = BreachAlertsClient(), profile: Profile) {
        self.client = client
        self.profile = profile
    }

    /// Loads breaches from Monitor endpoint using BreachAlertsClient.
    ///    - Parameters:
    ///         - completion: a completion handler for the processed breaches
    func loadBreaches(completion: @escaping (Maybe<Set<BreachRecord>>) -> Void) {
        if FileManager.default.fileExists(atPath: self.cacheURL.path) {
            guard let fileData = FileManager.default.contents(atPath: self.cacheURL.path) else {
                completion(Maybe(failure: BreachAlertsError(description: "failed to get data from breach.json")))
                return
            }

            // 1. check the last time breach endpoint was accessed
            guard let dateLastAccessedString = profile.prefs.stringForKey(BreachAlertsClient.dateKey) else {
                return
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "E, d MMM yyyy HH:mm:ss zzz"
            guard let dateLastAccessed = dateFormatter.date(from: dateLastAccessedString) else { return }

            let timeUntilNextUpdate = 60.0 * 60.0 * 24.0 * 3.0 // 3 days in seconds
            let shouldUpdateDate = Date(timeInterval: timeUntilNextUpdate, since: dateLastAccessed)

            // 2a. if 3 days have passed since last update...
            if shouldUpdateDate.timeIntervalSinceNow >= timeUntilNextUpdate {

                // 3. check if the etag is different
                self.client.fetchEtag(endpoint: .breachedAccounts, profile: self.profile) { maybeEtag in
                    guard let etag = maybeEtag.successValue else { return }
                    let savedEtag = self.profile.prefs.stringForKey(BreachAlertsClient.etagKey)

                    // 4. if it is, refetch the data and hand entire Set of BreachRecords off
                    if etag != savedEtag {
                        self.fetchAndSaveBreaches(completion)
                    }
                }
            } else {
                // 2b. else, no need to refetch. decode local data and hand off
                decodeData(data: fileData, completion)
            }
        } else {
            // first time loading breaches, so fetch as normal and hand off
            self.fetchAndSaveBreaches(completion)
        }
    }

    /// Compares a list of logins to a list of breaches and returns breached logins.
    ///    - Parameters:
    ///         - logins: a list of logins to compare breaches to
    ///    - Returns:
    ///         - an array of LoginRecords of breaches in the original list.
    func findUserBreaches(_ logins: [LoginRecord]) -> Maybe<Set<LoginRecord>> {
        var result = Set<LoginRecord>()

        if self.breaches.count <= 0 {
            return Maybe(failure: BreachAlertsError(description: "cannot compare to an empty list of breaches"))
        } else if logins.count <= 0 {
            return Maybe(failure: BreachAlertsError(description: "cannot compare to an empty list of logins"))
        }

        let loginsDictionary = loginsByHostname(logins)
        for breach in self.breaches {
            guard let potentialUserBreaches = loginsDictionary[breach.domain] else {
                continue
            }
            for item in potentialUserBreaches {
                let pwLastChanged = TimeInterval(item.timePasswordChanged/1000)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                guard let breachDate = dateFormatter.date(from: breach.breachDate)?.timeIntervalSince1970, pwLastChanged < breachDate else {
                    continue
                }
                result.insert(item)
            }
        }
        return Maybe(success: result)
    }

    /// Helper function to create a dictionary of LoginRecords separated by hostname.
    /// - Parameters:
    ///     - logins: an array of LoginRecords to sort.
    /// - Returns:
    ///     - a dictionary of [String(<hostname>): [LoginRecord]].
    func loginsByHostname(_ logins: [LoginRecord]) -> [String: [LoginRecord]] {
        var result = [String: [LoginRecord]]()
        for login in logins {
            let base = baseDomainForLogin(login)
            if !result.keys.contains(base) {
                result[base] = [login]
            } else {
                result[base]?.append(login)
            }
        }
        return result
    }

    /// Helper function to find a breach associated with a LoginRecord.
    /// - Parameters:
    ///     - login: an array of LoginRecords to sort.
    /// - Returns:
    ///     - the first BreachRecord associated with login, if any.
    func breachRecordForLogin(_ login: LoginRecord) -> BreachRecord? {
        let baseDomain = self.baseDomainForLogin(login)
        for breach in self.breaches where breach.domain == baseDomain {
            let pwLastChanged = TimeInterval(login.timePasswordChanged/1000)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let breachDate = dateFormatter.date(from: breach.breachDate)?.timeIntervalSince1970, pwLastChanged < breachDate else {
                continue
            }
            return breach
        }
        return nil
    }

    // MARK: - Helper Functions
    private func baseDomainForLogin(_ login: LoginRecord) -> String {
        guard let result = login.hostname.asURL?.baseDomain else { return login.hostname }
        return result
    }

    private func fetchAndSaveBreaches(_ completion: @escaping (Maybe<Set<BreachRecord>>) -> Void) {
        self.client.fetchData(endpoint: .breachedAccounts, profile: self.profile) { maybeData in
            guard let fetchedData = maybeData.successValue else {
                return
            }
            try? FileManager.default.removeItem(atPath: self.cacheURL.path)
            FileManager.default.createFile(atPath: self.cacheURL.path, contents: fetchedData, attributes: nil)

            guard let data = FileManager.default.contents(atPath: self.cacheURL.path) else { return }
            self.decodeData(data: data, completion)
        }
    }

    private func decodeData(data: Data, _ completion: @escaping (Maybe<Set<BreachRecord>>) -> Void) {
        guard let decoded = try? JSONDecoder().decode(Set<BreachRecord>.self, from: data) else {
            print(BreachAlertsError(description: "JSON data decode failure"))
            return
        }

        self.breaches = decoded
        // remove for release
        self.breaches.insert(BreachRecord(
         name: "MockBreach",
         title: "A Mock Blockbuster Record",
         domain: "blockbuster.com",
         breachDate: "1970-01-02",
         description: "A mock BreachRecord for testing purposes."
        ))
        self.breaches.insert(BreachRecord(
         name: "MockBreach",
         title: "A Mock Lorem Ipsum Record",
         domain: "lipsum.com",
         breachDate: "1970-01-02",
         description: "A mock BreachRecord for testing purposes."
        ))
        self.breaches.insert(BreachRecord(
         name: "MockBreach",
         title: "A Mock Swift Breach Record",
         domain: "swift.org",
         breachDate: "1970-01-02",
         description: "A mock BreachRecord for testing purposes."
        ))

        completion(Maybe(success: self.breaches))
    }
}

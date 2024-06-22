// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Contains type definitions for remote settings used in the app

enum RemoteCollection: String {
    case searchTelemetry = "search-telemetry-v2"
}

enum Remotebucket: String {
    case defaultBucket = "main"
}

enum RemoteSettingsUtilError: Error {
    case decodingError
    case fetchError(Error)
}

// Collections that are to be fetched from the server
struct ServerCollection: Codable {
    let id: String
    let last_modified: Int
    let displayFields: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case last_modified
        case displayFields = "displayFields"
    }
}

struct ServerCollectionsResponse: Codable {
    let data: [ServerCollection]
}

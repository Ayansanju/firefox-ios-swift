// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation

enum ImageError: Error, CustomStringConvertible {

    enum BundleError: CustomStringConvertible {
        var description: String {
            switch self {
            case .noBundleRetrieved(let error), .imageFormatting(let error), .noImage(let error):
                return error
            }
        }

        case noBundleRetrieved(String)
        case imageFormatting(String)
        case noImage(String)
    }

    case unableToDownloadImage(String)
    case unableToGetFromBundle(BundleError)

    var description: String {
        switch self {
        case .unableToDownloadImage(let error):
            return "Unable to download image with reason: \(error)"
        case .unableToGetFromBundle(let error):
            return "\(error.description)"
        }
    }
}

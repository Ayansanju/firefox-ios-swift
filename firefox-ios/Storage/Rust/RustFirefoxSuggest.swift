// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import MozillaAppServices

public protocol RustFirefoxSuggestActor: Actor {
    /// Downloads and stores new Firefox Suggest suggestions.
    func ingest() async throws

    /// Searches the store for matching suggestions.
    func query(
        _ keyword: String,
        providers: [SuggestionProvider],
        limit: Int32
    ) async throws -> [RustFirefoxSuggestion]

    /// Interrupts any ongoing queries for suggestions.
    nonisolated func interruptReader()

    /// Interrupts all ongoing operations.
    nonisolated func interruptEverything()
}

/// An actor that wraps the synchronous Rust `SuggestStore` binding to execute
/// blocking operations on a dispatch queue.
public actor RustFirefoxSuggest: RustFirefoxSuggestActor {
    private let store: SuggestStore

    // Using a pair of serial queues lets read and write operations run
    // without blocking one another.
    private let writerQueue = DispatchQueue(label: "RustFirefoxSuggest.writer")
    private let readerQueue = DispatchQueue(label: "RustFirefoxSuggest.reader")

    public init(dataPath: String, cachePath: String, remoteSettingsConfig: RemoteSettingsConfig? = nil) throws {
        var builder = SuggestStoreBuilder()
            .dataPath(path: dataPath)
            .cachePath(path: cachePath)

        if let remoteSettingsConfig {
            builder = builder.remoteSettingsConfig(config: remoteSettingsConfig)
        }

        store = try builder.build()
    }

    public func ingest() async throws {
        // Ensure that the Rust networking stack has been initialized before
        // downloading new suggestions. This is safe to call multiple times.
        Viaduct.shared.useReqwestBackend()

        try await withCheckedThrowingContinuation { continuation in
            writerQueue.async(qos: .utility) {
                do {
                    try self.store.ingest(constraints: SuggestIngestionConstraints())
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func query(
        _ keyword: String,
        providers: [SuggestionProvider],
        limit: Int32
    ) async throws -> [RustFirefoxSuggestion] {
        return try await withCheckedThrowingContinuation { continuation in
            readerQueue.async(qos: .userInitiated) {
                do {
                    let suggestions = try self.store.query(query: SuggestionQuery(
                        keyword: keyword,
                        providers: providers,
                        limit: limit
                    )).compactMap(RustFirefoxSuggestion.init) ?? []
                    continuation.resume(returning: suggestions)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public nonisolated func interruptReader() {
        store.interrupt()
    }

    public nonisolated func interruptEverything() {
        store.interrupt(kind: .readWrite)
    }
}

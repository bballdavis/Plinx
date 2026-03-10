import XCTest
import PlinxCore
@testable import Plinx

/// Live tests that compare what Plex reports as an "Other Videos" item's thumbnail (via
/// browse + full metadata) against what our model resolves via `preferredThumbPath`.
///
/// "Other Videos" libraries (agent = none) contain items that Plex returns as `type=movie`
/// in browse responses. The tests verify that `MediaItem.preferredThumbPath` resolves to the
/// same thumb Plex provides directly, ensuring we never accidentally return a parent/folder
/// cover instead of the item's own artwork.
///
/// Run via:
///   ./scripts/live_library_parity_tests.sh
/// or manually with real Plex credentials in test_creds.yaml.
@MainActor
final class ClipThumbnailParityLiveTests: XCTestCase {

    // MARK: - Tests

    /// Fetches all items from each Other Videos library and asserts that the thumb path we
    /// resolve from the browse response (`MediaItem.preferredThumbPath`) matches the `thumb`
    /// field returned directly by Plex in that same response.
    ///
    /// Other Videos libraries use agent=none; their items are `type=movie` in browse responses.
    /// This catches regressions where `preferredThumbPath` falls through to a folder/parent
    /// cover instead of the item's own user-set thumbnail.
    func test_clipBrowse_preferredThumbMatchesPlexThumb() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickOtherVideoLibraries(context: context)

        var totalChecked = 0
        var failures: [String] = []

        for library in libraries {
            guard let sectionId = library.sectionId else { continue }

            let sectionRepository = try SectionRepository(context: context)
            var start = 0
            let pageSize = 50

            repeat {
                let queryItems = [URLQueryItem(name: "excludeAllLeaves", value: "0")]
                let response = try await sectionRepository.getSectionBrowseItems(
                    path: "/library/sections/\(sectionId)/all",
                    queryItems: queryItems,
                    pagination: PlexPagination(start: start, size: pageSize)
                )
                let metadata = response.mediaContainer.metadata ?? []

                for entry in metadata {
                    guard case let .item(plexItem) = entry else { continue }
                    // Other Videos items are type=movie (agent=none), not type=clip.
                    // We test all item types the library returns.

                    let mediaItem = MediaItem(plexItem: plexItem)
                    let resolvedPath = mediaItem.preferredThumbPath
                    let plexThumb = plexItem.thumb

                    totalChecked += 1

                    if resolvedPath != plexThumb {
                        failures.append(
                            """
                            [\(library.title)] "\(plexItem.title)" (type=\(plexItem.type) ratingKey=\(plexItem.ratingKey)):
                              Plex thumb:    \(plexThumb ?? "<nil>")
                              Resolved path: \(resolvedPath ?? "<nil>")
                              parentThumb:   \(plexItem.parentThumb ?? "<nil>")
                              grandparentThumb: \(plexItem.grandparentThumb ?? "<nil>")
                            """
                        )
                    }
                }

                let total = response.mediaContainer.totalSize ?? (start + metadata.count)
                start += metadata.count
                if start >= total || metadata.isEmpty { break }
            } while true
        }

        guard totalChecked > 0 else {
            XCTFail("No items found in Other Videos libraries — is the library empty?")
            return
        }

        if failures.isEmpty {
            print("✓ \(totalChecked) item(s) all resolve preferredThumbPath == Plex thumb")
        } else {
            let report = failures.joined(separator: "\n\n")
            XCTFail(
                "\(failures.count) item(s) out of \(totalChecked) have a mismatched thumb path:\n\n\(report)"
            )
        }
    }

    /// For a sample of items from each Other Videos library, fetches the full metadata record
    /// (single-item endpoint) and compares the `thumb` to what the browse response returns.
    ///
    /// If browse `thumb` differs from full-metadata `thumb`, Plex returns a different image
    /// in list context vs single-item context. In that case we should use the full-metadata
    /// thumb for downloads rather than the browse thumb.
    func test_clipFullMetadata_thumbMatchesBrowseThumb() async throws {
        let context = try await makeLiveContextOrSkip()
        let libraries = try await pickOtherVideoLibraries(context: context)

        let metadataRepository = try MetadataRepository(context: context)
        let sectionRepository = try SectionRepository(context: context)

        var totalChecked = 0
        var mismatches: [String] = []

        for library in libraries {
            guard let sectionId = library.sectionId else { continue }

            // Only sample up to 20 items per library to keep the test fast.
            var itemsToCheck: [PlexItem] = []

            let queryItems = [URLQueryItem(name: "excludeAllLeaves", value: "0")]
            let response = try await sectionRepository.getSectionBrowseItems(
                path: "/library/sections/\(sectionId)/all",
                queryItems: queryItems,
                pagination: PlexPagination(start: 0, size: 50)
            )

            for entry in response.mediaContainer.metadata ?? [] {
                guard case let .item(plexItem) = entry else { continue }
                itemsToCheck.append(plexItem)
                if itemsToCheck.count >= 20 { break }
            }

            for browseItem in itemsToCheck {
                let fullResponse = try await metadataRepository.getMetadata(ratingKey: browseItem.ratingKey)
                guard let fullItem = fullResponse.mediaContainer.metadata?.first else { continue }

                totalChecked += 1
                let browseThumb = browseItem.thumb
                let fullThumb = fullItem.thumb

                if browseThumb != fullThumb {
                    mismatches.append(
                        """
                        [\(library.title)] "\(browseItem.title)" (type=\(browseItem.type) ratingKey=\(browseItem.ratingKey)):
                          Browse thumb:       \(browseThumb ?? "<nil>")
                          Full-metadata thumb: \(fullThumb ?? "<nil>")
                          Browse parentThumb:  \(browseItem.parentThumb ?? "<nil>")
                          Full parentThumb:    \(fullItem.parentThumb ?? "<nil>")
                        """
                    )
                }
            }
        }

        guard totalChecked > 0 else {
            throw XCTSkip("No items found in Other Videos libraries.")
        }

        if !mismatches.isEmpty {
            let report = mismatches.joined(separator: "\n\n")
            XCTFail(
                "\(mismatches.count) clip(s) have a different thumb in browse vs full-metadata responses:\n\n\(report)\n\n"
                + "If thumb differs, Plex is returning a different image for the list endpoint. "
                + "We must use the full-metadata thumb rather than the browse thumb for downloads."
            )
        } else {
            print("✓ \(totalChecked) clip(s): browse thumb == full-metadata thumb")
        }
    }

    // MARK: - Helpers (shared with LibraryFilteringParityLiveTests)

    private func makeLiveContextOrSkip() async throws -> PlexAPIContext {
        let serverRaw = credential(named: "PLINX_PLEX_SERVER_URL")
        let token = credential(named: "PLINX_PLEX_TOKEN")

        guard let serverRaw, !serverRaw.isEmpty,
              let token, !token.isEmpty else {
            throw XCTSkip("Live Plex credentials are not configured. Populate test_creds.yaml.")
        }
        guard let serverURL = URL(string: serverRaw),
              let host = serverURL.host,
              let scheme = serverURL.scheme else {
            XCTFail("Invalid PLINX_PLEX_SERVER_URL: \(serverRaw)")
            throw XCTSkip("Cannot run without valid server URL.")
        }

        let context = PlexAPIContext()
        await context.waitForBootstrap()
        context.setAuthToken(token)

        let connection = PlexCloudResource.Connection(
            scheme: scheme,
            address: host,
            port: serverURL.port ?? (scheme.lowercased() == "https" ? 443 : 80),
            uri: serverURL,
            isLocal: true,
            isRelay: false,
            isIPv6: host.contains(":")
        )
        let resource = PlexCloudResource(
            name: "Plinx Live Test",
            clientIdentifier: "plinx-live-tests",
            accessToken: token,
            connections: [connection]
        )
        do {
            try await context.selectServer(resource)
        } catch {
            throw XCTSkip("Failed to connect to Plex server: \(error.localizedDescription)")
        }
        return context
    }

    private func credential(named key: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let v = env[key], !v.isEmpty { return v }
        if let v = env["SIMCTL_CHILD_\(key)"], !v.isEmpty { return v }
        if let v = UserDefaults.standard.string(forKey: key), !v.isEmpty { return v }
        return yamlCredential(named: key)
    }

    private func yamlCredential(named key: String) -> String? {
        guard let yamlPath = locateTestCredsYAML(),
              let content = try? String(contentsOfFile: yamlPath, encoding: .utf8) else { return nil }
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let sep = line.firstIndex(of: ":") else { continue }
            let parsedKey = line[..<sep].trimmingCharacters(in: .whitespaces)
            guard parsedKey == key else { continue }
            var value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")), value.count >= 2 {
                value.removeFirst(); value.removeLast()
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func locateTestCredsYAML() -> String? {
        let fm = FileManager.default
        // Most reliable in the iOS Simulator: the file is bundled as a test resource.
        if let bundlePath = Bundle(for: Self.self).path(forResource: "test_creds", ofType: "yaml") {
            return bundlePath
        }
        var current = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<5 {
            let candidate = current.appendingPathComponent("test_creds.yaml").path
            if fm.fileExists(atPath: candidate) { return candidate }
            current.deleteLastPathComponent()
        }
        var sourceURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { sourceURL.deleteLastPathComponent() }
        let sourceCandidate = sourceURL.appendingPathComponent("test_creds.yaml").path
        return fm.fileExists(atPath: sourceCandidate) ? sourceCandidate : nil
    }

    private func pickOtherVideoLibraries(context: PlexAPIContext) async throws -> [Library] {
        let libraryStore = LibraryStore(context: context)
        try await libraryStore.loadLibraries()
        let candidates = libraryStore.libraries.filter {
            $0.sectionId != nil && (
                $0.isNoneAgentLibrary || ($0.type != .movie && $0.type != .show)
            )
        }
        guard !candidates.isEmpty else {
            throw XCTSkip("No Other Videos-style library found on this Plex server.")
        }
        return candidates
    }
}

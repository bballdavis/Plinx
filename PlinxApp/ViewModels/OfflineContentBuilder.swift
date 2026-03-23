import Foundation
import PlinxCore

struct OfflineHomeSection: Identifiable, Hashable {
    enum Layout: Hashable {
        case portrait
        case landscape
    }

    let id: String
    let title: String
    let items: [DownloadItem]
    let layout: Layout
}

struct OfflineLibraryGroup: Identifiable, Hashable {
    let library: Library
    let items: [DownloadItem]

    var id: String {
        library.id
    }
}

struct OfflineContentSnapshot: Hashable {
    let homeSections: [OfflineHomeSection]
    let libraries: [OfflineLibraryGroup]
}

enum OfflineContentBuilder {
    static func buildSnapshot(
        downloadItems: [DownloadItem],
        libraries: [Library],
        policy: SafetyPolicy,
    ) -> OfflineContentSnapshot {
        let resolvedItems = resolvedItems(from: downloadItems, libraries: libraries, policy: policy)
        let libraryGroups = buildLibraryGroups(from: resolvedItems, libraries: libraries)
        let homeSections = buildHomeSections(from: resolvedItems, libraryGroups: libraryGroups)
        return OfflineContentSnapshot(homeSections: homeSections, libraries: libraryGroups)
    }

    private static func resolvedItems(
        from downloadItems: [DownloadItem],
        libraries: [Library],
        policy: SafetyPolicy,
    ) -> [(item: DownloadItem, library: Library)] {
        let librariesBySectionID: [Int: Library] = Dictionary(uniqueKeysWithValues: libraries.compactMap { library in
            guard let sectionId = library.sectionId else { return nil }
            return (sectionId, library)
        })

        return downloadItems
            .filter(\.isPlayable)
            .compactMap { item in
                let library = resolveLibrary(for: item, librariesBySectionID: librariesBySectionID)
                guard isAllowed(item: item, in: library, policy: policy) else { return nil }
                return (item, library)
            }
    }

    private static func buildLibraryGroups(
        from resolvedItems: [(item: DownloadItem, library: Library)],
        libraries: [Library]
    ) -> [OfflineLibraryGroup] {
        let orderByLibraryID = Dictionary(uniqueKeysWithValues: libraries.enumerated().map { ($0.element.id, $0.offset) })

        // Group by library.id (not the full Library struct).  Two items from the
        // same Plex section can produce Library structs that differ in title/type
        // if some have artworkLayoutStyle=landscape and others don't (e.g. a mix of
        // videos from a YouTube library where the agent wasn't stored at download
        // time).  Grouping by id and picking the "best" representative library
        // prevents duplicate ForEach keys that break NavigationLink taps.
        var groupedByID: [String: (library: Library, items: [DownloadItem])] = [:]

        for (item, library) in resolvedItems {
            if var existing = groupedByID[library.id] {
                existing.items.append(item)
                // Prefer the "other video" (none-agent) classification when there
                // is a conflict, so YouTube / Home Videos libraries aren't shown
                // under the generic "Movies" label.
                if library.isNoneAgentLibrary && !existing.library.isNoneAgentLibrary {
                    existing.library = library
                }
                groupedByID[library.id] = existing
            } else {
                groupedByID[library.id] = (library: library, items: [item])
            }
        }

        return groupedByID.values
            .map { pair in
                OfflineLibraryGroup(
                    library: pair.library,
                    items: pair.items.sorted(by: compareRecency)
                )
            }
            .sorted { lhs, rhs in
                let lhsOrder = orderByLibraryID[lhs.library.id] ?? Int.max
                let rhsOrder = orderByLibraryID[rhs.library.id] ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.library.title.localizedCaseInsensitiveCompare(rhs.library.title) == .orderedAscending
            }
    }

    private static func buildHomeSections(
        from resolvedItems: [(item: DownloadItem, library: Library)],
        libraryGroups: [OfflineLibraryGroup]
    ) -> [OfflineHomeSection] {
        var sections: [OfflineHomeSection] = []

        let continueWatching = resolvedItems
            .map(\.item)
            .filter { item in
                (item.metadata.viewOffset ?? 0) > 0 && (item.metadata.viewCount ?? 0) == 0
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.metadata.lastPlayedAt ?? lhs.createdAt
                let rhsDate = rhs.metadata.lastPlayedAt ?? rhs.createdAt
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.createdAt > rhs.createdAt
            }

        if !continueWatching.isEmpty {
            sections.append(
                OfflineHomeSection(
                    id: "continueWatching",
                    title: "Continue Watching",
                    items: continueWatching,
                    layout: .landscape
                )
            )
        }

        let movieItems = resolvedItems
            .filter { HomeLibraryGrouping.isMoviesOrTV($0.library) && $0.library.type == .movie }
            .map(\.item)
            .sorted(by: compareRecency)
        if !movieItems.isEmpty {
            sections.append(
                OfflineHomeSection(
                    id: "recentMovies",
                    title: "Recently Added Movies",
                    items: movieItems,
                    layout: .portrait
                )
            )
        }

        let showItems = resolvedItems
            .filter { HomeLibraryGrouping.isMoviesOrTV($0.library) && $0.library.type == .show }
            .map(\.item)
            .sorted(by: compareRecency)
        if !showItems.isEmpty {
            sections.append(
                OfflineHomeSection(
                    id: "recentTV",
                    title: "Recently Added TV",
                    items: showItems,
                    layout: .portrait
                )
            )
        }

        let otherVideoGroups = libraryGroups.filter { HomeLibraryGrouping.isOtherVideo($0.library) }
        for group in otherVideoGroups where !group.items.isEmpty {
            sections.append(
                OfflineHomeSection(
                    id: "otherVideos.\(group.id)",
                    title: group.library.title,
                    items: group.items,
                    layout: .landscape
                )
            )
        }

        return sections
    }

    private static func resolveLibrary(
        for item: DownloadItem,
        librariesBySectionID: [Int: Library]
    ) -> Library {
        if let sectionId = item.metadata.sourceLibrarySectionID,
           let matchedLibrary = librariesBySectionID[sectionId] {
            return matchedLibrary
        }

        let title: String
        let type: PlexItemType
        let agent: String
        let itemType = item.metadata.type

        if itemType == .clip
            || item.metadata.resolvedArtworkLayoutStyle == .landscape
            || item.metadata.sourceLibraryAgent?.lowercased().contains("none") == true {
            title = "Other Videos"
            type = .clip
            agent = "tv.plex.agents.none"
        } else if itemType == .episode || itemType == .season || itemType == .show {
            title = "TV Shows"
            type = .show
            agent = ""
        } else {
            title = "Movies"
            type = .movie
            agent = ""
        }

        return Library(
            id: syntheticLibraryID(for: item, title: title),
            title: title,
            type: type,
            sectionId: item.metadata.sourceLibrarySectionID,
            agent: agent
        )
    }

    private static func syntheticLibraryID(for item: DownloadItem, title: String) -> String {
        if let sectionId = item.metadata.sourceLibrarySectionID {
            return "offline.section.\(sectionId)"
        }
        return "offline.\(title.replacingOccurrences(of: " ", with: "-").lowercased())"
    }

    private static func isAllowed(item: DownloadItem, in library: Library, policy: SafetyPolicy) -> Bool {
        // Items that were downloaded while online already passed the safety filter
        // at that time.  Individual episodes and personal-media clips often have no
        // stored contentRating (Plex only attaches ratings at the show / library
        // level), so the "exclude unrated" gate would incorrectly hide them offline.
        // We keep the rating ceiling check fully intact — only the allowUnrated flag
        // is overridden so that missing-rating items are not silently dropped.
        let effectivePolicy = SafetyPolicy(
            labelMatchMode: policy.labelMatchMode,
            maxMovieRating: policy.maxMovieRating,
            maxTVRating: policy.maxTVRating,
            allowUnrated: true
        )
        return StrimrAdapter.isAllowed(.playable(item.metadata.localMediaItem), policy: effectivePolicy)
    }

    private static func compareRecency(_ lhs: DownloadItem, _ rhs: DownloadItem) -> Bool {
        lhs.createdAt > rhs.createdAt
    }
}
import Foundation
import Observation
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// ContentSafetyGate — the one content decision every provider goes through
// ─────────────────────────────────────────────────────────────────────────────
//
// `SafeMediaServices` asks this gate about every item a provider returns, on
// Plex and Jellyfin, iOS and tvOS. The app keeps `policy` in sync with the
// parent's settings and `isParentUnlocked` in sync with
// `ParentalAccessCoordinator`.
//
// Decisions:
//   • A title is judged on its own `contentRating` (Plex `contentRating`;
//     on Jellyfin the stricter of `OfficialRating` and `CustomRating`, see
//     `JellyfinContentRating`), parsed by PlinxCore's
//     `ContentRatingNormalizer` and checked with `SafetyInterceptor`.
//   • Missing or unrecognized rating → rejected unless `policy.allowUnrated`.
//     Adult-only ratings (NC-17, X, 18) → always rejected.
//   • The rating's own scale picks the ceiling: TV ratings against the TV
//     ceiling, movie ratings against the movie ceiling, whatever the item kind.
//   • Seasons and episodes are also judged against their series' rating:
//     both must pass, and one without a rating of its own takes the series'
//     rating instead of counting as unrated. Servers rarely rate seasons and
//     episodes (Jellyfin almost never), so without this every unrated episode
//     of an R or TV-MA series would pass once a parent allows unrated content.
//     One without a rating whose series' rating is unknown is rejected under
//     every policy; one with a rating is then judged on its own.
//   • Collections and playlists are containers: they are listed, and their
//     entries are filtered one by one when opened. They are listed without the
//     artwork and counts the server builds from all of their entries (a
//     composite poster shows blocked titles too).
//   • Server items carry no Plinx labels, so label policies see none (a policy
//     that requires a label rejects everything, which fails closed).
//
// Series ratings. `SafeMediaServices` calls `learnSeries` with every title a
// provider returns before it filters them: the gate keeps the rating of every
// series it sees, and looks up (unfiltered, through the provider) each series
// whose seasons or episodes it is about to judge and has not confirmed since
// launch. The synchronous checks after the boundary (player, launcher,
// downloads) then judge against what it learned. On iOS the ratings are kept
// in the app's caches (`SeriesRatingStore`: series IDs and rating text, no
// titles), so downloaded episodes are still judged against their series
// offline.
//
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class ContentSafetyGate {
    static let shared = ContentSafetyGate(seriesRatingStore: SeriesRatingStore.onDevice)

    /// Looks a series up on its provider, unfiltered: the gate needs the series' own rating to judge its seasons and
    /// episodes.
    typealias SeriesLookup = @MainActor (_ seriesID: String) async throws -> MediaItem

    /// Starts at the strictest default (G, TV-Y, no unrated content) until the app applies the parent's settings.
    var policy: SafetyPolicy {
        didSet {
            guard policy != oldValue else { return }
            interceptor = SafetyInterceptor(policy: policy)
            revision += 1
        }
    }

    /// Parent-only abilities (server management, playlist edits, subtitle downloads) work only while this is true.
    var isParentUnlocked: Bool

    /// Bumped whenever `policy` changes, so screens and caches built under the old policy reload.
    private(set) var revision = 0

    @ObservationIgnored private var interceptor: SafetyInterceptor

    /// The rating of every series the gate has seen or looked up, by series.
    @ObservationIgnored private var seriesRatings: [MediaIdentity: SeriesRating] = [:]
    @ObservationIgnored private var seriesLookups: [MediaIdentity: Task<Void, Never>] = [:]
    /// When each failed lookup failed, so a listing paged in many requests does not ask for the same series each time.
    @ObservationIgnored private var failedSeriesLookups: [MediaIdentity: Date] = [:]
    @ObservationIgnored private var hasUnsavedSeriesRatings = false
    @ObservationIgnored private var pendingSeriesRatingSave: Task<Void, Never>?
    @ObservationIgnored private let seriesRatingStore: SeriesRatingStore?

    /// - Parameter seriesRatingStore: Where learned series ratings are kept between launches; `nil` keeps them in
    ///   memory only.
    init(
        policy: SafetyPolicy = .ratingOnly(),
        isParentUnlocked: Bool = false,
        seriesRatingStore: SeriesRatingStore? = nil,
    ) {
        self.policy = policy
        self.isParentUnlocked = isParentUnlocked
        interceptor = SafetyInterceptor(policy: policy)
        self.seriesRatingStore = seriesRatingStore
        seriesRatings = seriesRatingStore?.load() ?? [:]
    }

    /// A season or episode must pass on its own rating and on its series' (see `judgedRatings(of:)`).
    func isAllowed(_ item: MediaItem) -> Bool {
        guard let ratings = judgedRatings(of: item) else { return false }
        return ratings.allSatisfy { interceptor.isAllowed(Self.plinxItem(item, contentRating: $0)) }
    }

    /// Containers are listed; `shown(_:)` says how.
    func isAllowed(_ item: MediaDisplayItem) -> Bool {
        switch item {
        case let .playable(media):
            isAllowed(media)
        case .collection, .playlist:
            true
        }
    }

    /// What kid-facing screens may show of an item: `nil` when it is blocked. Collections and playlists are listed
    /// without the artwork and counts their server builds from every entry, blocked ones included: a Plex composite
    /// or a Jellyfin collage would draw the posters of blocked titles. Their screens draw a plain tile instead.
    func shown(_ item: MediaDisplayItem) -> MediaDisplayItem? {
        switch item {
        case let .playable(media):
            isAllowed(media) ? item : nil
        case let .collection(collection):
            MediaDisplayItem.collection(Self.listed(collection))
        case let .playlist(playlist):
            MediaDisplayItem.playlist(Self.listed(playlist))
        }
    }

    /// Why an item is allowed or rejected, for parent-facing diagnostics. Never shown to children.
    func decision(for item: MediaItem) -> FilterDecision {
        guard let ratings = judgedRatings(of: item) else { return .rejected(reason: .missingRating) }
        for rating in ratings {
            let decision = interceptor.explain(Self.plinxItem(item, contentRating: rating))
            guard decision == .allowed else { return decision }
        }
        return .allowed
    }

    static func plinxItem(_ item: MediaItem) -> PlinxMediaItem {
        plinxItem(item, contentRating: item.contentRating)
    }

    private static func plinxItem(_ item: MediaItem, contentRating: String?) -> PlinxMediaItem {
        PlinxMediaItem(id: item.id, title: item.title, labels: [], contentRating: contentRating)
    }

    /// A collection without its server artwork and entry count.
    static func listed(_ collection: CollectionMediaItem) -> CollectionMediaItem {
        CollectionMediaItem(
            id: collection.id,
            key: collection.key,
            guid: collection.guid,
            type: collection.type,
            title: collection.title,
            summary: collection.summary,
            thumbPath: nil,
            childCount: nil,
            minYear: collection.minYear,
            maxYear: collection.maxYear,
            server: collection.server,
        )
    }

    /// A playlist without its server composite, entry count and running time.
    static func listed(_ playlist: PlaylistMediaItem) -> PlaylistMediaItem {
        PlaylistMediaItem(
            id: playlist.id,
            key: playlist.key,
            guid: playlist.guid,
            type: playlist.type,
            title: playlist.title,
            summary: playlist.summary,
            compositePath: nil,
            duration: nil,
            leafCount: nil,
            playlistType: playlist.playlistType,
            isSmart: playlist.isSmart,
            server: playlist.server,
        )
    }
}

// MARK: - Series ratings

/// What the gate knows of a series' rating.
struct SeriesRating: Equatable {
    /// The series' own rating; `nil` when it has none.
    var contentRating: String?
    /// Confirmed by its provider since launch. An unconfirmed rating (kept from an earlier launch, or a missing rating
    /// in a listing, which may only have been left out of it) is used, and looked up again when next needed.
    var isConfirmed: Bool
    var seenAt: Date
}

extension ContentSafetyGate {
    /// A series that could not be looked up is asked for again after this long.
    static let failedLookupRetryInterval: TimeInterval = 30

    /// The series a season or episode belongs to. Plex and Jellyfin give an episode's series as its grandparent; a
    /// season's series is its grandparent on Jellyfin and its parent on Plex. `nil` for every other kind.
    static func seriesIdentity(of item: MediaItem) -> MediaIdentity? {
        let seriesID: String? = switch item.type {
        case .episode:
            item.grandparentRatingKey
        case .season:
            item.grandparentRatingKey ?? item.parentRatingKey
        case .movie, .series, .clip, .collection, .playlist, .folder, .unknown:
            nil
        }
        guard let seriesID, !seriesID.isEmpty else { return nil }
        return MediaIdentity(server: item.identity.server, itemID: seriesID)
    }

    /// The rating the gate knows for a series, if any.
    func seriesRating(for series: MediaIdentity) -> SeriesRating? {
        seriesRatings[series]
    }

    /// Learns the rating of every series among `titles`, and looks up the series of every season and episode among
    /// them whose rating is not confirmed since launch. Call it with what a provider returned before judging it. A
    /// lookup that fails leaves the series unknown, so its unrated seasons and episodes stay blocked.
    func learnSeries(of titles: [MediaItem], lookup: @escaping SeriesLookup) async {
        for title in titles where title.type == .series {
            remember(series: title, confirmed: false)
        }
        var pending: [MediaIdentity] = []
        var seen: Set<MediaIdentity> = []
        let now = Date()
        for title in titles {
            guard let series = Self.seriesIdentity(of: title),
                  seriesRatings[series]?.isConfirmed != true,
                  !recentlyFailed(series, now: now),
                  seen.insert(series).inserted
            else { continue }
            pending.append(series)
        }
        // Started together; a lookup another request already started is shared.
        let tasks = pending.map { seriesLookupTask(for: $0, lookup: lookup) }
        for task in tasks {
            await task.value
        }
        saveSeriesRatingsSoon()
    }

    /// Writes what changed to the store now. Otherwise changes are written a moment after they happen, so paging
    /// through a library does not write once per page.
    func saveSeriesRatings() {
        pendingSeriesRatingSave?.cancel()
        pendingSeriesRatingSave = nil
        guard hasUnsavedSeriesRatings, let seriesRatingStore else { return }
        hasUnsavedSeriesRatings = false
        seriesRatingStore.save(seriesRatings)
    }

    private func recentlyFailed(_ series: MediaIdentity, now: Date) -> Bool {
        guard let failedAt = failedSeriesLookups[series] else { return false }
        return now.timeIntervalSince(failedAt) < Self.failedLookupRetryInterval
    }

    func learnSeries(in items: [MediaDisplayItem], lookup: @escaping SeriesLookup) async {
        await learnSeries(of: items.compactMap(\.playableItem), lookup: lookup)
    }

    func learnSeries(in items: [LibraryBrowseItem], lookup: @escaping SeriesLookup) async {
        let titles = items.compactMap { item -> MediaItem? in
            guard case let .media(media) = item else { return nil }
            return media.playableItem
        }
        await learnSeries(of: titles, lookup: lookup)
    }

    func learnSeries(in hubs: [Hub], lookup: @escaping SeriesLookup) async {
        await learnSeries(in: hubs.flatMap(\.items), lookup: lookup)
    }

    func learnSeries(in rows: [HomeRow], lookup: @escaping SeriesLookup) async {
        let titles = rows.flatMap { row in
            row.items.compactMap(\.playableItem) + row.copies.values.flatMap(\.self)
        }
        await learnSeries(of: titles, lookup: lookup)
    }

    func learnSeries(in content: MediaDetailContent, lookup: @escaping SeriesLookup) async {
        var titles = [content.media] + content.seasons + content.episodes
        titles += [content.parentSeries, content.onDeck].compactMap(\.self)
        titles += content.relatedHubs.flatMap { $0.items.compactMap(\.playableItem) }
        await learnSeries(of: titles, lookup: lookup)
    }

    func learnSeries(in entries: [PlaylistEntry], lookup: @escaping SeriesLookup) async {
        await learnSeries(in: entries.map(\.media), lookup: lookup)
    }

    func learnSeries(in queue: PlaybackQueue, lookup: @escaping SeriesLookup) async {
        await learnSeries(of: queue.items.map(\.media), lookup: lookup)
    }

    /// The ratings an item is judged on; every one must pass. A movie, series or clip: its own. A season or episode:
    /// its own and its series', or its series' alone when it has none of its own (it takes the series' rating rather
    /// than counting as unrated). `nil` for a season or episode without a rating whose series' rating is unknown: it
    /// is rejected whatever the policy. One with a rating whose series is unknown is judged on its own rating.
    private func judgedRatings(of item: MediaItem) -> [String?]? {
        guard item.type == .episode || item.type == .season else { return [item.contentRating] }
        let ownRating = Self.presentRating(item.contentRating)
        let series = Self.seriesIdentity(of: item).flatMap { seriesRatings[$0] }
        switch (ownRating, series) {
        case let (ownRating?, series?):
            return [ownRating, series.contentRating]
        case let (ownRating?, nil):
            return [ownRating]
        case let (nil, series?):
            return [series.contentRating]
        case (nil, nil):
            return nil
        }
    }

    /// `nil` for a missing or blank rating.
    private static func presentRating(_ rating: String?) -> String? {
        guard let rating, !rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return rating
    }

    /// A rating the provider gave always counts. A missing one counts when the series was looked up (`confirmed`),
    /// and otherwise only when nothing is known yet: it never replaces a rating, and the series is still looked up.
    private func remember(series: MediaItem, confirmed: Bool) {
        let rating = Self.presentRating(series.contentRating)
        let known = seriesRatings[series.identity]
        guard rating != nil || confirmed || known == nil else { return }
        let entry = SeriesRating(contentRating: rating, isConfirmed: rating != nil || confirmed, seenAt: Date())
        if known?.contentRating != entry.contentRating || known == nil {
            hasUnsavedSeriesRatings = true
        }
        seriesRatings[series.identity] = entry
    }

    private func seriesLookupTask(for series: MediaIdentity, lookup: @escaping SeriesLookup) -> Task<Void, Never> {
        if let running = seriesLookups[series] {
            return running
        }
        // Not tied to the request that started it: a cancelled screen does not cancel a lookup another one waits for.
        let task = Task { @MainActor in
            let found = try? await lookup(series.itemID)
            self.seriesLookups[series] = nil
            // Only the series itself, from the same server, can stand for it.
            guard let found, found.identity == series, found.type == .series else {
                self.failedSeriesLookups[series] = Date()
                return
            }
            self.failedSeriesLookups[series] = nil
            self.remember(series: found, confirmed: true)
        }
        seriesLookups[series] = task
        return task
    }

    private func saveSeriesRatingsSoon() {
        guard hasUnsavedSeriesRatings, seriesRatingStore != nil, pendingSeriesRatingSave == nil else { return }
        pendingSeriesRatingSave = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.saveSeriesRatings()
        }
    }
}

/// Keeps learned series ratings on the device, so seasons and episodes (downloads above all) are still judged against
/// their series without the server. Only series IDs and rating text are kept, never titles, in the app's caches: the
/// system may purge them, which only means a series is looked up again (or, offline, its unrated episodes stay hidden).
struct SeriesRatingStore {
    let fileURL: URL
    /// The most recently seen series are kept beyond this many.
    var capacity = 5000

    /// iOS keeps them (downloads play offline). tvOS has no offline mode, and keeps them in memory only.
    static var onDevice: SeriesRatingStore? {
        #if os(tvOS)
            return nil
        #else
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return nil
            }
            return SeriesRatingStore(fileURL: caches.appendingPathComponent("SeriesRatings.json", isDirectory: false))
        #endif
    }

    private struct Record: Codable {
        let server: String
        let series: String
        let rating: String?
        let seenAt: Date
    }

    /// Read back unconfirmed: each is looked up again when next needed online.
    func load() -> [MediaIdentity: SeriesRating] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [:] }
        var ratings: [MediaIdentity: SeriesRating] = [:]
        for record in records {
            guard let server = ServerIdentity(stableKey: record.server), !record.series.isEmpty else { continue }
            ratings[MediaIdentity(server: server, itemID: record.series)] = SeriesRating(
                contentRating: record.rating,
                isConfirmed: false,
                seenAt: record.seenAt,
            )
        }
        return ratings
    }

    func save(_ ratings: [MediaIdentity: SeriesRating]) {
        let records = ratings
            .sorted { $0.value.seenAt > $1.value.seenAt }
            .prefix(max(capacity, 0))
            .map { series, rating in
                Record(
                    server: series.server.stableKey,
                    series: series.itemID,
                    rating: rating.contentRating,
                    seenAt: rating.seenAt,
                )
            }
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Why `SafeMediaServices` refused a request.
enum ContentSafetyError: LocalizedError, Equatable {
    /// The title is above the parent's ceiling, unrated, or adult-only.
    case blocked
    /// A parent-only action while the parental gate is locked.
    case parentApprovalRequired
    /// A feature Plinx does not offer (Live TV).
    case unavailable

    var errorDescription: String? {
        switch self {
        case .blocked, .unavailable:
            String(localized: "safety.content.unavailable", defaultValue: "This isn't available.", table: "Plinx")
        case .parentApprovalRequired:
            String(localized: "safety.parentApprovalRequired", defaultValue: "Ask a grown-up to unlock this.", table: "Plinx")
        }
    }
}

// MARK: - Filtering

extension ContentSafetyGate {
    func filter(_ items: [MediaItem]) -> [MediaItem] {
        items.filter(isAllowed)
    }

    /// Allowed titles, and containers as `shown(_:)` lists them.
    func filter(_ items: [MediaDisplayItem]) -> [MediaDisplayItem] {
        items.compactMap { shown($0) }
    }

    /// Throws `ContentSafetyError.blocked` for a title the policy rejects.
    func requireAllowed(_ item: MediaItem) throws -> MediaItem {
        guard isAllowed(item) else { throw ContentSafetyError.blocked }
        return item
    }

    /// The hub with only allowed items, containers listed as `shown(_:)` lists them; `nil` when filtering emptied it.
    /// A hub the server sent empty stays as it was.
    func filter(_ hub: Hub) -> Hub? {
        guard hub.hasItems else { return hub }
        let shown = filter(hub.items)
        guard !shown.isEmpty else { return nil }
        guard shown != hub.items else { return hub }
        return Hub(
            id: hub.id,
            key: hub.key,
            hubKey: hub.hubKey,
            title: hub.title,
            // Only containers changed: the server's size still counts what the hub holds.
            size: shown.count == hub.items.count ? hub.size : shown.count,
            more: hub.more,
            items: shown,
            server: hub.server,
        )
    }

    func filter(_ hubs: [Hub]) -> [Hub] {
        hubs.compactMap(filter)
    }

    /// The row with only allowed items and copies; `nil` when filtering emptied it, unless `keepsEmptiedRows`.
    func filter(_ row: HomeRow, keepsEmptiedRows: Bool = false) -> HomeRow? {
        let hub: Hub
        if let filtered = filter(row.hub) {
            hub = filtered
        } else if keepsEmptiedRows {
            hub = Hub(
                id: row.hub.id,
                key: row.hub.key,
                hubKey: row.hub.hubKey,
                title: row.hub.title,
                size: 0,
                more: row.hub.more,
                items: [],
                server: row.hub.server,
            )
        } else {
            return nil
        }
        let shownIDs = Set(hub.items.compactMap(\.playableItem).map(\.identity))
        var copies: [MediaIdentity: [MediaItem]] = [:]
        for (identity, items) in row.copies where shownIDs.contains(identity) {
            let allowed = filter(items)
            if !allowed.isEmpty {
                copies[identity] = allowed
            }
        }
        return HomeRow(
            id: row.id,
            kind: row.kind,
            style: row.style,
            hub: hub,
            serverName: row.serverName,
            libraryName: row.libraryName,
            isExcludedFromServerHome: row.isExcludedFromServerHome,
            copies: copies,
        )
    }

    func filter(_ rows: [HomeRow], keepsEmptiedRows: Bool = false) -> [HomeRow] {
        rows.compactMap { filter($0, keepsEmptiedRows: keepsEmptiedRows) }
    }

    func filter(_ content: HomeContent) -> HomeContent {
        HomeContent(rows: filter(content.rows))
    }

    func filter(_ candidates: [FeaturedCandidate]) -> [FeaturedCandidate] {
        candidates.filter { isAllowed($0.item) }
    }

    func filter(_ entries: [PlaylistEntry]) -> [PlaylistEntry] {
        entries.filter { isAllowed($0.media) }
    }

    /// Folders are containers: their titles are filtered when the folder is opened.
    func isAllowed(_ item: LibraryBrowseItem) -> Bool {
        switch item {
        case let .media(media):
            isAllowed(media)
        case .folder:
            true
        }
    }

    /// What may be shown of a browse item: `nil` when it is blocked; collections and playlists as `shown(_:)` lists
    /// them.
    func shown(_ item: LibraryBrowseItem) -> LibraryBrowseItem? {
        switch item {
        case let .media(media):
            shown(media).map(LibraryBrowseItem.media)
        case .folder:
            item
        }
    }

    func filter(_ items: [LibraryBrowseItem]) -> [LibraryBrowseItem] {
        items.compactMap { shown($0) }
    }

    /// Detail of an allowed title: throws when the title itself is blocked, and drops every blocked title it links to.
    func filter(_ content: MediaDetailContent) throws -> MediaDetailContent {
        _ = try requireAllowed(content.media)
        return MediaDetailContent(
            media: content.media,
            parentSeries: content.parentSeries.flatMap { isAllowed($0) ? $0 : nil },
            onDeck: content.onDeck.flatMap { isAllowed($0) ? $0 : nil },
            seasons: filter(content.seasons),
            episodes: filter(content.episodes),
            cast: content.cast,
            relatedHubs: filter(content.relatedHubs),
        )
    }

    /// The queue without blocked titles. Throws when the title it starts with is blocked.
    func filter(_ queue: PlaybackQueue) throws -> PlaybackQueue {
        guard queue.items.indices.contains(queue.currentIndex) else {
            guard queue.items.allSatisfy({ isAllowed($0.media) }) else { throw ContentSafetyError.blocked }
            return queue
        }
        let current = queue.items[queue.currentIndex]
        _ = try requireAllowed(current.media)
        var filtered = queue
        filtered.items = queue.items.filter { isAllowed($0.media) }
        filtered.currentIndex = filtered.items.firstIndex { $0.id == current.id } ?? 0
        return filtered
    }
}

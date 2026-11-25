import Foundation

/// The server and profile a pre-fork Plinx download was enrolled for, as its `index.json` stored it beside the
/// download (`accessScope`). `DownloadManager`'s legacy index migration turns it into the download's `ownerID`.
///
/// It matches a Plex `MediaOwner`: `serverIdentifier` is the server's machine identifier and
/// `accessScopeIdentifier` the Plex Home user UUID of the profile.
struct DownloadAccessScope: Codable, Hashable, Sendable {
    let serverIdentifier: String
    let accessScopeIdentifier: String

    init(serverIdentifier: String, accessScopeIdentifier: String) {
        self.serverIdentifier = serverIdentifier
        self.accessScopeIdentifier = accessScopeIdentifier
    }

    init(owner: MediaOwner) {
        serverIdentifier = owner.server.id
        accessScopeIdentifier = owner.userID
    }
}

/// How the persisted download list loaded. The JSON fallback index is never overwritten after a failed read, and
/// pre-fork ownership is only imported into a list that loaded completely (`LegacyDownloadOwnership`).
enum DownloadPersistedIndexState: Equatable {
    case missing
    case loaded
    case unreadable
    case corrupt

    /// Only a complete load: importing ownership into a partial list would consume the pre-fork record while some
    /// of the downloads it describes are still waiting for recovery.
    var permitsOwnershipMigration: Bool {
        self == .loaded
    }

    var permitsPersistence: Bool {
        self == .missing || self == .loaded
    }
}

/// Non-sensitive persistence failures, reported without paths, tokens or server text.
enum DownloadPersistenceFailure: Error {
    case indexEncode
    case indexWrite
    case indexRead
    case indexDecode
    case legacyIndexEntriesDropped
    case metadataEncode
    case metadataWrite
}

enum DownloadStatus: String, Codable, Hashable {
    case queued
    case preparing
    case downloading
    case completed
    case failed

    var isActive: Bool {
        switch self {
        case .queued, .preparing, .downloading:
            true
        case .completed, .failed:
            false
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        // Pre-fork Plinx persisted `deciding` while Plex chose a transcode route; anything unknown fails safe.
        self = DownloadStatus(rawValue: rawValue) ?? (rawValue == "deciding" ? .preparing : .failed)
    }
}

/// The card shape Plinx's offline downloads grid uses for a download.
enum DownloadArtworkLayoutStyle: String, Codable, Hashable {
    case portrait
    case landscape

    var isPortrait: Bool {
        self == .portrait
    }

    static func `default`(for kind: MediaKind) -> DownloadArtworkLayoutStyle {
        switch kind {
        case .movie, .series, .season, .episode:
            .portrait
        case .clip, .collection, .playlist, .folder, .unknown:
            .landscape
        }
    }
}

struct DownloadedSubtitleFile: Codable, Hashable {
    var fileName: String
    var title: String?
    var language: String?
    var codec: String?
    var isForced: Bool
    var isHearingImpaired: Bool
}

/// Where pre-fork Plinx left off playing a download offline. It kept this only in its download index
/// (`metadata.viewOffset` and `metadata.lastPlayedAt`) and never sent it to the server.
/// `LegacyDownloadIndex.restoreResumePoints` moves it into the owner's offline progress once the download has an owner.
struct LegacyDownloadResumePoint: Hashable {
    /// Seconds into the video; always greater than zero.
    var position: TimeInterval
    /// When the download was last played, or nil when the index did not say.
    var lastPlayedAt: Date?
}

struct DownloadedMediaMetadata: Codable, Hashable {
    var identity: MediaIdentity?
    var itemID: String
    var guid: String
    var type: MediaKind
    var title: String
    var summary: String?
    var genres: [String]
    var year: Int?
    var duration: TimeInterval?
    var viewCount: Int?
    var contentRating: String?
    var studio: String?
    var tagline: String?
    var parentRatingKey: String?
    var grandparentRatingKey: String?
    var grandparentTitle: String?
    var parentTitle: String?
    var parentIndex: Int?
    var index: Int?
    var posterFileName: String?
    var videoFileName: String
    var fileSize: Int64?
    var requestedQuality: TranscodeQualityPreset
    var effectiveQuality: TranscodeQualityPreset
    var audioTitle: String?
    var subtitleTitle: String?
    var subtitleFiles: [DownloadedSubtitleFile]
    var versionID: String?
    /// Only set when the item had several versions, so a mismatched episode stays visible in the list.
    var versionLabel: String?
    var createdAt: Date
    /// Plinx's offline grid shape for this download (for example landscape for home videos). Nil follows the type.
    var artworkLayoutStyle: DownloadArtworkLayoutStyle?
    /// An offline resume point pre-fork Plinx saved, until it is moved into the owner's offline progress. It stays
    /// here while the download has no owner.
    var legacyResumePoint: LegacyDownloadResumePoint?

    var resolvedArtworkLayoutStyle: DownloadArtworkLayoutStyle {
        artworkLayoutStyle ?? DownloadArtworkLayoutStyle.default(for: type)
    }

    var prefersPortraitArtwork: Bool {
        resolvedArtworkLayoutStyle.isPortrait
    }

    init(
        identity: MediaIdentity,
        guid: String,
        type: MediaKind,
        title: String,
        summary: String?,
        genres: [String],
        year: Int?,
        duration: TimeInterval?,
        viewCount: Int?,
        contentRating: String?,
        studio: String?,
        tagline: String?,
        parentRatingKey: String?,
        grandparentRatingKey: String?,
        grandparentTitle: String?,
        parentTitle: String?,
        parentIndex: Int?,
        index: Int?,
        posterFileName: String?,
        videoFileName: String,
        fileSize: Int64?,
        requestedQuality: TranscodeQualityPreset,
        effectiveQuality: TranscodeQualityPreset,
        audioTitle: String?,
        subtitleTitle: String?,
        versionID: String? = nil,
        versionLabel: String? = nil,
        createdAt: Date,
    ) {
        self.identity = identity
        itemID = identity.itemID
        self.guid = guid
        self.type = type
        self.title = title
        self.summary = summary
        self.genres = genres
        self.year = year
        self.duration = duration
        self.viewCount = viewCount
        self.contentRating = contentRating
        self.studio = studio
        self.tagline = tagline
        self.parentRatingKey = parentRatingKey
        self.grandparentRatingKey = grandparentRatingKey
        self.grandparentTitle = grandparentTitle
        self.parentTitle = parentTitle
        self.parentIndex = parentIndex
        self.index = index
        self.posterFileName = posterFileName
        self.videoFileName = videoFileName
        self.fileSize = fileSize
        self.requestedQuality = requestedQuality
        self.effectiveQuality = effectiveQuality
        self.audioTitle = audioTitle
        self.subtitleTitle = subtitleTitle
        subtitleFiles = []
        self.versionID = versionID
        self.versionLabel = versionLabel
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case itemID
        case provider
        case serverIdentifier
        case ratingKey
        case guid
        case type
        case title
        case summary
        case genres
        case year
        case duration
        case viewCount
        case contentRating
        case studio
        case tagline
        case parentRatingKey
        case grandparentRatingKey
        case grandparentTitle
        case parentTitle
        case parentIndex
        case index
        case posterFileName
        case videoFileName
        case fileSize
        case requestedQuality
        case effectiveQuality
        case audioTitle
        case subtitleTitle
        case subtitleFiles
        case subtitleFileName
        case subtitleLanguage
        case subtitleCodec
        case subtitleIsForced
        case versionID
        case versionLabel
        case createdAt
        case artworkLayoutStyle
        case viewOffset
        case lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
            ?? container.decode(String.self, forKey: .ratingKey)

        if let decodedIdentity = try container.decodeIfPresent(MediaIdentity.self, forKey: .identity) {
            identity = decodedIdentity
            itemID = decodedIdentity.itemID
        } else if
            let provider = try container.decodeIfPresent(MediaProvider.self, forKey: .provider),
            let serverIdentifier = try container.decodeIfPresent(String.self, forKey: .serverIdentifier)
        {
            identity = MediaIdentity(
                server: ServerIdentity(provider: provider, id: serverIdentifier),
                itemID: itemID,
            )
        } else {
            identity = nil
        }

        guid = try container.decode(String.self, forKey: .guid)
        type = try container.decode(MediaKind.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        genres = try container.decode([String].self, forKey: .genres)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
        contentRating = try container.decodeIfPresent(String.self, forKey: .contentRating)
        studio = try container.decodeIfPresent(String.self, forKey: .studio)
        tagline = try container.decodeIfPresent(String.self, forKey: .tagline)
        parentRatingKey = try container.decodeIfPresent(String.self, forKey: .parentRatingKey)
        grandparentRatingKey = try container.decodeIfPresent(String.self, forKey: .grandparentRatingKey)
        grandparentTitle = try container.decodeIfPresent(String.self, forKey: .grandparentTitle)
        parentTitle = try container.decodeIfPresent(String.self, forKey: .parentTitle)
        parentIndex = try container.decodeIfPresent(Int.self, forKey: .parentIndex)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        posterFileName = try container.decodeIfPresent(String.self, forKey: .posterFileName)
        videoFileName = try container.decode(String.self, forKey: .videoFileName)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        requestedQuality = try container.decodeIfPresent(
            TranscodeQualityPreset.self,
            forKey: .requestedQuality,
        ) ?? .original
        effectiveQuality = try container.decodeIfPresent(
            TranscodeQualityPreset.self,
            forKey: .effectiveQuality,
        ) ?? requestedQuality
        audioTitle = try container.decodeIfPresent(String.self, forKey: .audioTitle)
        subtitleTitle = try container.decodeIfPresent(String.self, forKey: .subtitleTitle)
        if let files = try container.decodeIfPresent([DownloadedSubtitleFile].self, forKey: .subtitleFiles) {
            subtitleFiles = files
        } else if let legacyFileName = try container.decodeIfPresent(String.self, forKey: .subtitleFileName) {
            subtitleFiles = try [DownloadedSubtitleFile(
                fileName: legacyFileName,
                title: subtitleTitle,
                language: container.decodeIfPresent(String.self, forKey: .subtitleLanguage),
                codec: container.decodeIfPresent(String.self, forKey: .subtitleCodec),
                isForced: container.decodeIfPresent(Bool.self, forKey: .subtitleIsForced) ?? false,
                isHearingImpaired: false,
            )]
        } else {
            subtitleFiles = []
        }
        versionID = try container.decodeIfPresent(String.self, forKey: .versionID)
        versionLabel = try container.decodeIfPresent(String.self, forKey: .versionLabel)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        artworkLayoutStyle = try? container.decodeIfPresent(DownloadArtworkLayoutStyle.self, forKey: .artworkLayoutStyle)
        // A damaged resume point costs only the resume point, never the download.
        if let position = try? container.decodeIfPresent(TimeInterval.self, forKey: .viewOffset),
           position.isFinite, position > 0
        {
            legacyResumePoint = LegacyDownloadResumePoint(
                position: position,
                lastPlayedAt: try? container.decodeIfPresent(Date.self, forKey: .lastPlayedAt),
            )
        } else {
            legacyResumePoint = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(identity, forKey: .identity)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(guid, forKey: .guid)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(genres, forKey: .genres)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(viewCount, forKey: .viewCount)
        try container.encodeIfPresent(contentRating, forKey: .contentRating)
        try container.encodeIfPresent(studio, forKey: .studio)
        try container.encodeIfPresent(tagline, forKey: .tagline)
        try container.encodeIfPresent(parentRatingKey, forKey: .parentRatingKey)
        try container.encodeIfPresent(grandparentRatingKey, forKey: .grandparentRatingKey)
        try container.encodeIfPresent(grandparentTitle, forKey: .grandparentTitle)
        try container.encodeIfPresent(parentTitle, forKey: .parentTitle)
        try container.encodeIfPresent(parentIndex, forKey: .parentIndex)
        try container.encodeIfPresent(index, forKey: .index)
        try container.encodeIfPresent(posterFileName, forKey: .posterFileName)
        try container.encode(videoFileName, forKey: .videoFileName)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encode(requestedQuality, forKey: .requestedQuality)
        try container.encode(effectiveQuality, forKey: .effectiveQuality)
        try container.encodeIfPresent(audioTitle, forKey: .audioTitle)
        try container.encodeIfPresent(subtitleTitle, forKey: .subtitleTitle)
        try container.encode(subtitleFiles, forKey: .subtitleFiles)
        try container.encodeIfPresent(versionID, forKey: .versionID)
        try container.encodeIfPresent(versionLabel, forKey: .versionLabel)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(artworkLayoutStyle, forKey: .artworkLayoutStyle)
        // Written back in the pre-fork shape, so a resume point waiting for an owner survives the offline database.
        try container.encodeIfPresent(legacyResumePoint?.position, forKey: .viewOffset)
        try container.encodeIfPresent(legacyResumePoint?.lastPlayedAt, forKey: .lastPlayedAt)
    }

    var subtitle: String? {
        switch type {
        case .episode:
            if let grandparentTitle, let parentIndex, let index {
                return "\(grandparentTitle) • S\(parentIndex)E\(index)"
            }
            return grandparentTitle ?? parentTitle
        case .movie:
            return year.map(String.init)
        case .season:
            return parentTitle
        case .series:
            return nil
        case .clip, .collection, .playlist, .folder, .unknown:
            return nil
        }
    }
}

struct DownloadItem: Codable, Identifiable, Hashable {
    var id: String
    var status: DownloadStatus
    var progress: Double
    var bytesWritten: Int64
    var totalBytes: Int64
    var taskIdentifier: Int?
    var remoteReference: MediaDownloadRemoteReference?
    var trackPreference: MediaTrackPreference?
    var allowsCellularAccess: Bool? = nil
    var errorMessage: String?
    var metadata: DownloadedMediaMetadata
    var ownerID: String? = nil
    var enrichmentState: DownloadEnrichmentState? = nil

    var identity: MediaIdentity? {
        metadata.identity
    }

    var itemID: String {
        metadata.itemID
    }

    var isPlayable: Bool {
        status == .completed
    }

    var createdAt: Date {
        metadata.createdAt
    }

    /// A failed download can be retried unless the same media was downloaded again since.
    func canRetry(among items: [DownloadItem]) -> Bool {
        guard status == .failed else { return false }
        return !items.contains { other in
            other.id != id && other.identity == identity && other.ownerID == ownerID && other.status != .failed
        }
    }

    /// Media built from the stored metadata alone: what safety checks of a download look at.
    var localMediaItem: MediaItem {
        metadata.localMediaItem(downloadID: id, thumbPath: nil)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case progress
        case bytesWritten
        case totalBytes
        case taskIdentifier
        case remoteReference
        case trackPreference
        case allowsCellularAccess
        case errorMessage
        case metadata
        case ownerID
        case enrichmentState
    }
}

extension DownloadItem {
    /// Tolerates the pre-fork Plinx index (`index.json`), so an upgrade never loses the family's downloads:
    /// its own Plex download-queue reference shape cannot be resumed and is dropped, and a transfer that was still
    /// being prepared on the server becomes a failed, retryable download.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(DownloadStatus.self, forKey: .status)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        bytesWritten = try container.decodeIfPresent(Int64.self, forKey: .bytesWritten) ?? 0
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        taskIdentifier = try container.decodeIfPresent(Int.self, forKey: .taskIdentifier)
        var hasRemoteReference = false
        if container.contains(.remoteReference) {
            hasRemoteReference = try !container.decodeNil(forKey: .remoteReference)
        }
        if hasRemoteReference {
            remoteReference = try? container.decode(MediaDownloadRemoteReference.self, forKey: .remoteReference)
        } else {
            remoteReference = nil
        }
        trackPreference = try? container.decodeIfPresent(MediaTrackPreference.self, forKey: .trackPreference)
        allowsCellularAccess = try container.decodeIfPresent(Bool.self, forKey: .allowsCellularAccess)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        metadata = try container.decode(DownloadedMediaMetadata.self, forKey: .metadata)
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID)
        enrichmentState = try? container.decodeIfPresent(DownloadEnrichmentState.self, forKey: .enrichmentState)

        let lostRemoteReference = hasRemoteReference && remoteReference == nil
        if status.isActive, lostRemoteReference || (status == .preparing && remoteReference == nil) {
            status = .failed
            taskIdentifier = nil
            errorMessage = String(localized: "downloads.status.interrupted")
        }
    }
}

extension DownloadedMediaMetadata {
    /// Media built from the stored metadata alone, for safety checks and offline rows.
    var localMediaItem: MediaItem {
        localMediaItem(downloadID: nil, thumbPath: nil)
    }

    /// A download without a stored server (written before multi-server support) gets a placeholder server that
    /// matches no real one, so it never resolves against a live service.
    func localMediaItem(downloadID: String?, thumbPath: String?) -> MediaItem {
        let resolvedIdentity = identity ?? MediaIdentity(
            server: ServerIdentity(provider: .plex, id: "legacy-download:\(downloadID ?? itemID)"),
            itemID: itemID,
        )
        return MediaItem(
            id: itemID,
            identity: resolvedIdentity,
            guid: guid,
            summary: summary,
            title: title,
            type: type,
            parentRatingKey: parentRatingKey,
            grandparentRatingKey: grandparentRatingKey,
            genres: genres,
            year: year,
            duration: duration,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: contentRating,
            studio: studio,
            tagline: tagline,
            thumbPath: thumbPath,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: viewCount,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: grandparentTitle,
            parentTitle: parentTitle,
            parentIndex: parentIndex,
            index: index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        )
    }
}

struct DownloadStorageSummary: Equatable {
    var totalBytes: Int64
    var usedBytes: Int64
    var availableBytes: Int64
    var downloadsBytes: Int64

    static let empty = DownloadStorageSummary(
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        downloadsBytes: 0,
    )
}

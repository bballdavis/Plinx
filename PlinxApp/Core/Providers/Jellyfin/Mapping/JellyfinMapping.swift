import Foundation
import PlinxCore

extension MediaTrackMetadata {
    init(jellyfinStream: JellyfinMediaStream) {
        self.init(
            id: jellyfinStream.index,
            sourceIndex: jellyfinStream.index,
            codec: jellyfinStream.codec ?? "",
            title: jellyfinStream.title,
            displayTitle: jellyfinStream.displayTitle
                ?? jellyfinStream.title
                ?? jellyfinStream.language
                ?? jellyfinStream.codec
                ?? "",
            language: jellyfinStream.language,
            isDefault: jellyfinStream.isDefault ?? false,
            isForced: jellyfinStream.isForced ?? false,
            isHearingImpaired: jellyfinStream.isHearingImpaired ?? false,
        )
    }
}

extension MediaItem {
    init(jellyfinItem: JellyfinItem, server: ServerIdentity) {
        let type = jellyfinItem.kind
        let primaryPath = JellyfinArtworkPath.make(
            ownerID: jellyfinItem.id,
            type: "Primary",
            tag: jellyfinItem.imageTags?["Primary"],
        )
        let backdropPath = JellyfinArtworkPath.make(
            ownerID: jellyfinItem.id,
            type: "Backdrop",
            tag: jellyfinItem.backdropImageTags?.first,
        )
        let seriesPath = JellyfinArtworkPath.make(
            ownerID: jellyfinItem.seriesID ?? jellyfinItem.id,
            type: "Primary",
            tag: jellyfinItem.seriesPrimaryImageTag,
        )
        // An episode or season backdrop would show its own content, so only the inherited series one is used.
        let grandparentArtPath: String? = if type == .episode || type == .season {
            jellyfinItem.parentBackdropItemID.flatMap {
                JellyfinArtworkPath.make(
                    ownerID: $0,
                    type: "Backdrop",
                    tag: jellyfinItem.parentBackdropImageTags?.first,
                )
            }
        } else {
            backdropPath
        }

        self.init(
            id: jellyfinItem.id,
            identity: MediaIdentity(server: server, itemID: jellyfinItem.id),
            guid: "jellyfin://\(server.id)/\(jellyfinItem.id)",
            summary: jellyfinItem.overview,
            title: jellyfinItem.name,
            type: type,
            parentRatingKey: jellyfinItem.parentID,
            grandparentRatingKey: jellyfinItem.seriesID,
            genres: jellyfinItem.genres ?? [],
            year: jellyfinItem.productionYear,
            releaseDate: jellyfinItem.premiereDate.flatMap(JellyfinDate.date(from:)),
            duration: jellyfinItem.duration,
            videoResolution: jellyfinItem.mediaSources?.first?.videoResolution,
            rating: jellyfinItem.communityRating,
            ratings: [
                jellyfinItem.communityRating.map {
                    MediaRating(source: .jellyfinCommunity, value: $0)
                },
                jellyfinItem.criticRating.map {
                    MediaRating(source: .jellyfinCritics, value: $0)
                },
            ].compactMap(\.self),
            contentRating: JellyfinContentRating.resolve(
                official: jellyfinItem.officialRating,
                custom: jellyfinItem.customRating,
            ),
            studio: jellyfinItem.studios?.first?.name,
            tagline: jellyfinItem.taglines?.first,
            thumbPath: primaryPath,
            artPath: backdropPath ?? primaryPath,
            artworkCornerColors: nil,
            viewOffset: jellyfinItem.resumePosition,
            viewCount: jellyfinItem.userData?.played == true ? max(1, jellyfinItem.userData?.playCount ?? 1) : 0,
            childCount: jellyfinItem.childCount ?? jellyfinItem.recursiveItemCount,
            leafCount: jellyfinItem.recursiveItemCount,
            viewedLeafCount: nil,
            watchState: MediaWatchState(
                isPlayed: jellyfinItem.userData?.played ?? false,
                playCount: jellyfinItem.userData?.playCount ?? 0,
                resumePosition: jellyfinItem.resumePosition,
                unplayedItemCount: jellyfinItem.userData?.unplayedItemCount,
                isFavorite: jellyfinItem.userData?.isFavorite ?? false,
            ),
            grandparentTitle: jellyfinItem.seriesName,
            parentTitle: jellyfinItem.seasonName,
            parentIndex: jellyfinItem.parentIndexNumber,
            index: jellyfinItem.indexNumber,
            grandparentThumbPath: seriesPath,
            grandparentArtPath: grandparentArtPath,
            // Jellyfin points this at the season, or at the series when the season has no poster.
            parentThumbPath: type == .episode ? jellyfinItem.parentPrimaryImageItemID.flatMap {
                JellyfinArtworkPath.make(ownerID: $0, type: "Primary", tag: jellyfinItem.parentPrimaryImageTag)
            } : nil,
            lastViewedAt: jellyfinItem.userData?.lastPlayedDate,
            externalIDs: ExternalIDs(providerIDs: jellyfinItem.providerIDs ?? [:]),
            logoPath: JellyfinArtworkPath.make(
                ownerID: jellyfinItem.id,
                type: "Logo",
                tag: jellyfinItem.imageTags?["Logo"],
            ),
            grandparentLogoPath: jellyfinItem.parentLogoItemID.flatMap {
                JellyfinArtworkPath.make(ownerID: $0, type: "Logo", tag: jellyfinItem.parentLogoImageTag)
            },
        )
    }
}

extension MediaDisplayItem {
    init?(jellyfinItem: JellyfinItem, server: ServerIdentity) {
        let media = MediaItem(jellyfinItem: jellyfinItem, server: server)
        switch jellyfinItem.kind {
        case .movie, .series, .season, .episode, .clip:
            self = .playable(media)
        case .collection:
            self = .collection(
                CollectionMediaItem(
                    id: media.id,
                    key: media.id,
                    guid: media.guid,
                    type: .collection,
                    title: media.title,
                    summary: media.summary,
                    thumbPath: media.thumbPath,
                    childCount: media.childCount,
                    minYear: nil,
                    maxYear: nil,
                    server: server,
                ),
            )
        case .playlist:
            self = .playlist(
                PlaylistMediaItem(
                    id: media.id,
                    key: media.id,
                    guid: media.guid,
                    type: .playlist,
                    title: media.title,
                    summary: media.summary,
                    compositePath: media.thumbPath,
                    duration: media.duration.map { Int($0 * 1000) },
                    leafCount: media.leafCount,
                    playlistType: "video",
                    server: server,
                ),
            )
        case .folder, .unknown:
            return nil
        }
    }
}

extension Library {
    init(jellyfinItem: JellyfinItem, server: ServerIdentity) {
        let type: MediaKind = switch jellyfinItem.collectionType?.lowercased() {
        case "tvshows": .series
        case "boxsets": .collection
        case "playlists": .playlist
        default: .movie
        }
        self.init(
            id: jellyfinItem.id,
            title: jellyfinItem.name,
            type: type,
            server: server,
        )
    }
}

extension Person {
    init(jellyfinPerson: JellyfinPerson) {
        self.init(
            id: jellyfinPerson.id,
            name: jellyfinPerson.name,
            thumbPath: JellyfinArtworkPath.make(
                ownerID: jellyfinPerson.id,
                type: "Primary",
                tag: jellyfinPerson.primaryImageTag,
            ),
        )
    }
}

/// The one rating Plinx judges and shows for a Jellyfin item.
///
/// Jellyfin keeps two ratings: `OfficialRating` from the title's metadata, and `CustomRating`, which an admin sets
/// to rate a title differently (Jellyfin's own parental controls use it in place of the official one). Plinx takes
/// the stricter of the two it can read, so a custom rating can tighten a recognized official rating but never
/// loosen it:
///   • an adult-only rating in either one wins;
///   • of two ratings `ContentRatingNormalizer` recognizes, the more severe wins (the official one on a tie);
///   • a rating Plinx cannot read never replaces one it can;
///   • when Plinx can read neither, the custom one wins, as on Jellyfin. Both count as unrated.
///
/// The result is stored as the item's `contentRating`, so the safety boundary, downloads and favorites all judge it.
enum JellyfinContentRating {
    static func resolve(official: String?, custom: String?) -> String? {
        let official = nonEmpty(official)
        guard let custom = nonEmpty(custom) else { return official }
        guard let official else { return custom }
        switch (ContentRatingNormalizer.classify(official), ContentRatingNormalizer.classify(custom)) {
        case (.adultOnly, _):
            return official
        case (_, .adultOnly):
            return custom
        case let (.rated(officialRating), .rated(customRating)):
            return customRating > officialRating ? custom : official
        case (.rated, .unrated):
            return official
        case (.unrated, .rated), (.unrated, .unrated):
            return custom
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

enum JellyfinArtworkPath {
    static func make(ownerID: String, type: String, tag: String?) -> String? {
        guard tag != nil else { return nil }
        return "jellyfin-artwork://\(ownerID)/\(type)?tag=\(tag ?? "")"
    }

    static func makeChapter(ownerID: String, index: Int, tag: String?) -> String {
        var components = URLComponents()
        components.scheme = "jellyfin-artwork"
        components.host = ownerID
        components.path = "/Chapter"
        components.queryItems = [URLQueryItem(name: "index", value: String(index))]
        if let tag, !tag.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "tag", value: tag))
        }
        return components.string ?? "jellyfin-artwork://\(ownerID)/Chapter?index=\(index)"
    }

    static func parse(_ value: String) -> (ownerID: String, type: String, index: Int?, tag: String?)? {
        guard let components = URLComponents(string: value),
              components.scheme == "jellyfin-artwork",
              let ownerID = components.host
        else { return nil }
        let type = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !type.isEmpty else { return nil }
        let index = components.queryItems?
            .first(where: { $0.name == "index" })?
            .value
            .flatMap(Int.init)
        let tag = components.queryItems?.first(where: { $0.name == "tag" })?.value
        return (ownerID, type, index, tag)
    }
}

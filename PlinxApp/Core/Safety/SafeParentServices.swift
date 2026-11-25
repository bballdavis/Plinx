import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Parent-only and disabled provider services behind the safety boundary.
//
// Server management and the rights behind it exist only while the parental
// gate is unlocked. Live TV is off: channels and programs carry no rating, so
// they cannot be filtered fail-closed (hard-fork plan D5).
// ─────────────────────────────────────────────────────────────────────────────

/// The server rights the user has, only while a parent has the gate unlocked; denied otherwise.
@MainActor
final class SafeAuthorizationService: MediaAuthorizationService {
    private let base: any MediaAuthorizationService
    private let gate: ContentSafetyGate

    init(base: any MediaAuthorizationService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    var authorization: MediaAuthorization {
        gate.isParentUnlocked ? base.authorization : .denied
    }
}

/// Server administration (refresh, match, artwork, metadata, deletion), refused while the parental gate is locked.
/// Screens already hide these actions when `MediaAuthorization` denies them; this is the second lock.
@MainActor
final class SafeManagementService: MediaManagementService {
    private let base: any MediaManagementService
    private let gate: ContentSafetyGate

    init(base: any MediaManagementService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    private var isUnlocked: Bool {
        gate.isParentUnlocked
    }

    private func requireParent() throws {
        guard isUnlocked else { throw ContentSafetyError.parentApprovalRequired }
    }

    func refreshMetadata(itemID: String) async throws {
        try requireParent()
        try await base.refreshMetadata(itemID: itemID)
    }

    var supportsAnalyze: Bool {
        isUnlocked && base.supportsAnalyze
    }

    func analyze(itemID: String) async throws {
        try requireParent()
        try await base.analyze(itemID: itemID)
    }

    func scanLibrary(id: String) async throws {
        try requireParent()
        try await base.scanLibrary(id: id)
    }

    func refreshLibraryMetadata(id: String) async throws {
        try requireParent()
        try await base.refreshLibraryMetadata(id: id)
    }

    func analyzeLibrary(id: String) async throws {
        try requireParent()
        try await base.analyzeLibrary(id: id)
    }

    var supportsLibraryTrash: Bool {
        isUnlocked && base.supportsLibraryTrash
    }

    func emptyLibraryTrash(id: String) async throws {
        try requireParent()
        try await base.emptyLibraryTrash(id: id)
    }

    func artworkKinds(for item: MediaItem) -> [EditableArtworkKind] {
        isUnlocked ? base.artworkKinds(for: item) : []
    }

    func artworkOptions(for item: MediaItem, kind: EditableArtworkKind) async throws -> [ArtworkOption] {
        try requireParent()
        return try await base.artworkOptions(for: item, kind: kind)
    }

    func selectArtwork(_ option: ArtworkOption, for item: MediaItem, kind: EditableArtworkKind) async throws {
        try requireParent()
        try await base.selectArtwork(option, for: item, kind: kind)
    }

    func uploadArtwork(_ upload: ArtworkUpload, for item: MediaItem, kind: EditableArtworkKind) async throws {
        try requireParent()
        try await base.uploadArtwork(upload, for: item, kind: kind)
    }

    func deletionImpact(of item: MediaItem) async throws -> MediaDeletionImpact {
        try requireParent()
        return try await base.deletionImpact(of: item)
    }

    func delete(_ item: MediaItem) async throws {
        try requireParent()
        try await base.delete(item)
    }

    func searchMatches(for item: MediaItem, title: String, year: Int?) async throws -> [MatchCandidate] {
        try requireParent()
        return try await base.searchMatches(for: item, title: title, year: year)
    }

    func applyMatch(_ candidate: MatchCandidate, to item: MediaItem) async throws {
        try requireParent()
        try await base.applyMatch(candidate, to: item)
    }

    var supportsUnmatch: Bool {
        isUnlocked && base.supportsUnmatch
    }

    func unmatch(itemID: String) async throws {
        try requireParent()
        try await base.unmatch(itemID: itemID)
    }

    func editableMetadataFields(for item: MediaItem) -> [MetadataField] {
        isUnlocked ? base.editableMetadataFields(for: item) : []
    }

    func loadMetadataDraft(for item: MediaItem) async throws -> MetadataDraft {
        try requireParent()
        return try await base.loadMetadataDraft(for: item)
    }

    func saveMetadata(_ draft: MetadataDraft, original: MetadataDraft, for item: MediaItem) async throws {
        try requireParent()
        try await base.saveMetadata(draft, original: original, for: item)
    }

    func metadataSuggestions(for field: MetadataField, item: MediaItem) async throws -> [String] {
        try requireParent()
        return try await base.metadataSuggestions(for: field, item: item)
    }

    func supportsAdvancedSettings(for item: MediaItem) -> Bool {
        isUnlocked && base.supportsAdvancedSettings(for: item)
    }

    func advancedSettings(itemID: String) async throws -> [ItemSetting] {
        try requireParent()
        return try await base.advancedSettings(itemID: itemID)
    }

    func updateAdvancedSetting(_ setting: ItemSetting, value: String, itemID: String) async throws {
        try requireParent()
        try await base.updateAdvancedSetting(setting, value: value, itemID: itemID)
    }
}

/// Live TV is not offered: the provider's service is never reached, so no channel, program or stream leaves it.
@MainActor
final class DisabledLiveTVService: MediaLiveTVService {
    var dvr: (any MediaDVRService)? {
        nil
    }

    var supportsServerCaptureBuffer: Bool {
        false
    }

    func isAvailable() async throws -> Bool {
        false
    }

    func channels() async throws -> [LiveTVChannel] {
        []
    }

    func programs(from _: Date, to _: Date) async throws -> [LiveTVProgram] {
        []
    }

    func onNow() async throws -> [LiveTVOnNowSection] {
        []
    }

    func setFavorite(_: Bool, channel _: LiveTVChannel) async throws {
        throw ContentSafetyError.unavailable
    }

    func reorderFavorites(_: [LiveTVChannel]) async throws {
        throw ContentSafetyError.unavailable
    }

    func startPlayback(
        channel _: LiveTVChannel,
        route _: LiveTVRoutePreference,
    ) async throws -> any LiveTVPlaybackSession {
        throw ContentSafetyError.unavailable
    }
}

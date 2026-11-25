#if !os(tvOS)
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DownloadAccessPolicy — which downloads the active profile sees and plays
// ─────────────────────────────────────────────────────────────────────────────
//
// Ownership is the download's own `ownerID` (`MediaOwner`: provider, server
// and server user), recorded by `DownloadManager` from the services that
// created it. A profile owns the downloads of the owners `DownloadManager`
// activated for it (`activateSession(services:)` online, `activateOwners(_:)`
// offline). Pre-fork downloads get the owner pre-fork Plinx recorded for them,
// once, at launch (`LegacyDownloadOwnership`). A download without an owner,
// for example one kept from before per-profile downloads, belongs to nobody:
// no profile sees or plays it, and only a parent lists it (to delete it).
//
// Content is re-checked through `ContentSafetyGate`, the same boundary every
// provider response goes through, on both the metadata stored with the
// download and the server metadata pinned for it. A download saved under an
// older, looser ceiling disappears as soon as a parent lowers it, and an
// unrated download stays hidden unless unrated content is allowed.
//
// Downloads are iOS only (the download stack is not in the tvOS target).
//
// ─────────────────────────────────────────────────────────────────────────────

/// Whether the active profile may see and use a download.
enum DownloadAccessDecision: Equatable {
    case allowed
    /// The title is above the parent's ceiling, unrated while unrated content is hidden, or adult-only.
    case blockedByContentPolicy
    /// The download belongs to another profile, account or server user.
    case wrongOwner
    /// The download has no recorded owner.
    case missingOwner
}

/// Fail-closed access decisions for the downloads of the active profile.
@MainActor
struct DownloadAccessPolicy {
    private let activeOwnerIDs: Set<String>
    private let gate: ContentSafetyGate
    private let pinnedMedia: @MainActor (DownloadItem) -> MediaItem?

    /// The content-policy revision these decisions were made under. Reading it when the policy is built (inside a
    /// view's body) makes the view re-evaluate its downloads when a parent changes the ceilings.
    let policyRevision: Int

    /// - Parameter gate: The content boundary to check against; `nil` is the app's shared gate.
    init(downloadManager: DownloadManager, gate: ContentSafetyGate? = nil) {
        self.init(
            activeOwnerIDs: downloadManager.activeOwnerIDs,
            gate: gate,
            pinnedMedia: { downloadManager.playbackMedia(for: $0) }
        )
    }

    /// - Parameters:
    ///   - gate: The content boundary to check against; `nil` is the app's shared gate.
    ///   - pinnedMedia: Server metadata kept for a download (its enriched offline record), checked in addition to
    ///     the metadata stored with the download.
    init(
        activeOwnerIDs: Set<String>,
        gate: ContentSafetyGate? = nil,
        pinnedMedia: @escaping @MainActor (DownloadItem) -> MediaItem? = { _ in nil }
    ) {
        let resolvedGate = gate ?? ContentSafetyGate.shared
        self.activeOwnerIDs = activeOwnerIDs
        self.gate = resolvedGate
        self.pinnedMedia = pinnedMedia
        policyRevision = resolvedGate.revision
    }

    func decision(for item: DownloadItem) -> DownloadAccessDecision {
        guard isAllowedByContentPolicy(item) else { return .blockedByContentPolicy }
        guard let ownerID = item.ownerID else { return .missingOwner }
        guard activeOwnerIDs.contains(ownerID) else { return .wrongOwner }
        return .allowed
    }

    /// The downloads the active profile may see, in the given order.
    func filter(_ items: [DownloadItem]) -> [DownloadItem] {
        items.filter { decision(for: $0) == .allowed }
    }

    /// Both the stored and the pinned metadata must pass the gate.
    func isAllowedByContentPolicy(_ item: DownloadItem) -> Bool {
        guard gate.isAllowed(item.localMediaItem) else { return false }
        if let pinned = pinnedMedia(item), !gate.isAllowed(pinned) {
            return false
        }
        return true
    }
}

/// What a tap on a downloads-grid or list entry does.
///
/// Only entries the access policy allows are ever actionable. A failed entry
/// offers Remove and Redownload instead of silently ignoring the tap.
enum DownloadTapAction: Equatable {
    case play
    case showFailureActions
    case none

    static func resolve(for item: DownloadItem, decision: DownloadAccessDecision) -> DownloadTapAction {
        guard decision == .allowed else { return .none }
        if item.isPlayable { return .play }
        return item.status == .failed ? .showFailureActions : .none
    }
}
#endif

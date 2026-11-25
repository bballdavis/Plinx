import Foundation

/// The product name Plinx reports to media servers: Plex's `X-Plex-Product` and
/// sign-in page, and Jellyfin's `Client` and device profile names.
///
/// Servers show it on the sign-in page, in the account's authorized devices and
/// in the server dashboard, so it follows the host app's display name instead of
/// a hard-coded upstream name. Only the display name changes on the wire; the
/// persisted client and device identifiers stay as they are so families stay
/// signed in.
enum PlexProductIdentity {
    static let name = productName(in: Bundle.main.infoDictionary)

    static func productName(in infoDictionary: [String: Any]?) -> String {
        let candidates = [
            infoDictionary?["CFBundleDisplayName"] as? String,
            infoDictionary?["CFBundleName"] as? String,
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Plinx"
    }
}

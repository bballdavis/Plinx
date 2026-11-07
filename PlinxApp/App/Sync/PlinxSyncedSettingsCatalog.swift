import Foundation
import PlinxCore

/// The preferences Plinx syncs through iCloud when a parent enables it, each
/// with an allow-list or shape check applied before a remote value is used.
///
/// Synced: content-rating ceilings, unrated filtering, touch lock, playback
/// volume cap, navigation and appearance choices, home-screen and library
/// layout, and library visibility.
///
/// Never synced (device- or secret-scoped): the parent PIN (Keychain), the
/// Youtarr connection and credentials, download quality and Wi-Fi rules,
/// download ownership, banner artwork count and hot reload (per device size),
/// and the sync switch itself.
@MainActor
enum PlinxSyncedSettingsCatalog {
    /// Upper bounds that keep a malformed remote value from bloating storage
    /// or the UI. Real libraries and sections are far below these.
    static let maximumIdentifierCount = 500
    static let maximumIdentifierLength = 256

    static func standard(
        defaults: UserDefaults = .standard,
        settingsManager: SettingsManager
    ) -> [PlinxSyncedSetting] {
        [
            // ── Parental controls ─────────────────────────────────────────
            choice("plinx.maxMovieRating", allowed: PlinxRating.movieRatings.map(\.rawValue), defaults: defaults),
            choice("plinx.maxTVRating", allowed: PlinxRating.tvRatings.map(\.rawValue), defaults: defaults),
            flag("plinx.excludeUnrated", defaults: defaults),
            flag("plinx.babyLockEnabled", defaults: defaults),
            PlinxSyncedSetting(
                name: "strimr.playback.maxVolumePercent",
                read: { .int(settingsManager.playback.maxVolumePercent) },
                apply: { value in
                    guard case .int(let percent) = value, (0...100).contains(percent) else { return false }
                    settingsManager.setMaxVolumePercent(percent)
                    return true
                }
            ),

            // ── Navigation and appearance ─────────────────────────────────
            flag(PlinxNavigationPreference.showSearchInMainNavigationStorageKey, defaults: defaults),
            choice("plinx.accentColorName", allowed: PlinxAccentColor.allCases.map(\.rawValue), defaults: defaults),
            choice(
                PlinxChromeButtonSizePreference.storageKey,
                allowed: PlinxChromeButtonSizePreference.allCases.map(\.rawValue),
                defaults: defaults
            ),
            flag(PlinxAnimationPreference.playfulAnimationsStorageKey, defaults: defaults),

            // ── Home screen and library layout ────────────────────────────
            flag("plinx.homeCombineMoviesTV", defaults: defaults),
            jsonIdentifierList("plinx.homeSectionOrder", defaults: defaults),
            jsonIdentifierList("plinx.homeLibraryOrder", defaults: defaults),
            jsonIdentifierList("plinx.homeHiddenLibraryIds", defaults: defaults),
            libraryViewSettings(defaults: defaults),
            PlinxSyncedSetting(
                name: "strimr.interface.hiddenLibraryIds",
                read: { .stringArray(settingsManager.interface.hiddenLibraryIds) },
                apply: { value in
                    guard case .stringArray(let ids) = value, isValidIdentifierList(ids) else { return false }
                    settingsManager.setHiddenLibraryIds(ids)
                    return true
                }
            ),
            PlinxSyncedSetting(
                name: "strimr.interface.displayCollections",
                read: { .bool(settingsManager.interface.displayCollections) },
                apply: { value in
                    guard case .bool(let enabled) = value else { return false }
                    settingsManager.setDisplayCollections(enabled)
                    return true
                }
            ),
        ]
    }

    // MARK: - Entry builders (UserDefaults-backed, keyed by their storage key)

    static func flag(_ key: String, defaults: UserDefaults) -> PlinxSyncedSetting {
        PlinxSyncedSetting(
            name: key,
            read: {
                guard defaults.object(forKey: key) != nil else { return nil }
                return .bool(defaults.bool(forKey: key))
            },
            apply: { value in
                guard case .bool(let flag) = value else { return false }
                defaults.set(flag, forKey: key)
                return true
            }
        )
    }

    static func choice(_ key: String, allowed: [String], defaults: UserDefaults) -> PlinxSyncedSetting {
        let allowedValues = Set(allowed)
        return PlinxSyncedSetting(
            name: key,
            read: { defaults.string(forKey: key).map(PlinxSyncValue.string) },
            apply: { value in
                guard case .string(let choice) = value, allowedValues.contains(choice) else { return false }
                defaults.set(choice, forKey: key)
                return true
            }
        )
    }

    /// A JSON-encoded `[String]` stored as a string, as `@AppStorage` keeps it.
    static func jsonIdentifierList(_ key: String, defaults: UserDefaults) -> PlinxSyncedSetting {
        PlinxSyncedSetting(
            name: key,
            read: { defaults.string(forKey: key).map(PlinxSyncValue.string) },
            apply: { value in
                guard
                    case .string(let json) = value,
                    let data = json.data(using: .utf8),
                    let ids = try? JSONDecoder().decode([String].self, from: data),
                    isValidIdentifierList(ids)
                else { return false }
                defaults.set(json, forKey: key)
                return true
            }
        )
    }

    static func libraryViewSettings(defaults: UserDefaults) -> PlinxSyncedSetting {
        let key = plinxLibraryViewStorageKey
        return PlinxSyncedSetting(
            name: key,
            read: { defaults.data(forKey: key).map(PlinxSyncValue.data) },
            apply: { value in
                guard
                    case .data(let data) = value,
                    let decoded = try? JSONDecoder().decode([String: PlinxLibraryViewSettings].self, from: data),
                    decoded.count <= maximumIdentifierCount,
                    decoded.allSatisfy({ libraryId, entry in
                        libraryId.count <= maximumIdentifierLength
                            && isValidIdentifierList(entry.hiddenRecommendSectionIds)
                            && isValidIdentifierList(entry.recommendSectionOrder)
                    })
                else { return false }
                defaults.set(data, forKey: key)
                return true
            }
        )
    }

    static func isValidIdentifierList(_ ids: [String]) -> Bool {
        ids.count <= maximumIdentifierCount && ids.allSatisfy { $0.count <= maximumIdentifierLength }
    }
}

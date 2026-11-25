import SwiftUI

/// What the player controls show.
struct PlayerControlsState {
    var media: MediaItem?
    var isPaused: Bool
    var badges: [PlayerControlBadge]
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var showsEndsAtTime: Bool
    var showsClock: Bool
    var isScrubbing: Bool
    var sleepTimer: SleepTimer
    var chapters: [MediaChapter]
    var showsChaptersOnTimeline: Bool
    var skipSegments: [SkipSegment]
    var scrubPreview: PlayerScrubPreview?
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var skipMarkerTitle: String?
    var isSharePlay: Bool
    var hasInfoPanel: Bool
    var live: PlayerLiveState?
    var settingsControl: PlayerSettingsControl?
    var showsSubtitleOffsetIndicator: Bool
    var settingsFocusGeneration: Int
    var isShowingPanel: Bool

    var seekBackwardSymbol: String {
        Self.seekSymbol(prefix: "gobackward", seconds: seekBackwardSeconds)
    }

    var seekForwardSymbol: String {
        Self.seekSymbol(prefix: "goforward", seconds: seekForwardSeconds)
    }

    /// SF Symbols only number some intervals; the others fall back on the plain arrow.
    private static func seekSymbol(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

struct PlayerLiveState {
    var behindLiveSeconds: Double
    var isAtLiveEdge: Bool
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
}

/// What the player controls can do.
struct PlayerControlsActions {
    var playPause: () -> Void
    var seekBackward: () -> Void
    var seekForward: () -> Void
    var scrubbingChanged: (Bool) -> Void
    var scrubbingCancelled: () -> Void
    var skipMarker: (() -> Void)?
    var showInfoPanel: () -> Void
    var userInteraction: () -> Void
    var showAudioSettings: () -> Void
    var showSubtitleSettings: () -> Void
    var showSettings: () -> Void
    var goLive: () -> Void
    var showLiveChannels: () -> Void
    var previousChannel: () -> Void
    var nextChannel: () -> Void
}

struct PlayerControlBadge: Identifiable {
    var id: String
    var title: String
    var systemImage: String?

    static func playback(resolution: String?, format: PlayerVideoFormatBadge?) -> [PlayerControlBadge] {
        var badges: [PlayerControlBadge] = []
        if let resolution {
            badges.append(PlayerControlBadge(id: "resolution", title: resolution))
        }
        if let format {
            badges.append(PlayerControlBadge(id: format.id, title: format.title, systemImage: "sparkles"))
        }
        return badges
    }
}

enum PlayerSettingsControl {
    case audio, subtitle, settings
}

/// Room the player controls take over the video, so subtitles, messages and statistics stay clear of them.
enum PlayerControlsMetrics {
    static let subtitleInset: CGFloat = 380
    /// With the info panel open.
    static let expandedSubtitleInset: CGFloat = 440
    static let feedbackBottomInset: CGFloat = 330
    static let statisticsTopInset: CGFloat = 150
    static let adjustmentBarBottomInset: CGFloat = 380
}

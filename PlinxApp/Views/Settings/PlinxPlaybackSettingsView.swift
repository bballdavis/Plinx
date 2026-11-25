import PlinxUI
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Player settings (parent-only)
//
// The kid-appropriate part of upstream's Playback, Audio and Subtitles pages,
// built on the shared `SettingsViewModel` bindings. Deliberately absent:
//   • default playback speed (Plinx removed speed control),
//   • external and custom external players (playback never leaves Plinx),
//   • the tvOS system player style (Plinx keeps its own player and timeline),
//   • Live TV options (Live TV is off for kids),
//   • automatic subtitle download (subtitle search is a parent-only server
//     write that the safety boundary refuses during a child's playback).
// The maximum volume stays on the Settings root as a safety control.
//
// Picture in Picture and background audio (iPhone and iPad only) are off by
// default. They work only because the iOS target declares the `audio`
// background mode (`UIBackgroundModes` in project.yml); without it iOS
// suspends Plinx and both toggles do nothing. While both are off, leaving the
// app closes the player (`PlayerBackgroundPolicy` in LifecycleManager.swift).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
struct PlinxPlaybackSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        let viewModel = SettingsViewModel(settingsManager: settingsManager)

        List {
            Section {
                PlinxSettingsChoice(
                    Text("settings.playback.nextEpisodeAutoplay"),
                    systemImage: "forward.end.fill",
                    selection: viewModel.nextEpisodeAutoplayBinding,
                    options: viewModel.nextEpisodeAutoplayOptions
                ) { option in
                    Text(verbatim: option.title)
                }

                PlinxSettingsChoice(
                    Text("settings.playback.defaultSleepTimer"),
                    systemImage: "moon.zzz.fill",
                    selection: viewModel.defaultSleepTimerBinding,
                    options: viewModel.defaultSleepTimerOptions
                ) { option in
                    Text(verbatim: viewModel.defaultSleepTimerTitle(option))
                }
            } header: {
                Text(verbatim: PlinxSettingsCopy.bedtimeSection)
            } footer: {
                Text(verbatim: PlinxSettingsCopy.bedtimeFooter)
            }

            Section {
                PlinxSettingsToggle(
                    Text("settings.playback.autoSkipIntros"),
                    systemImage: "forward.fill",
                    isOn: viewModel.autoSkipIntrosBinding
                )
                PlinxSettingsToggle(
                    Text("settings.playback.autoSkipCredits"),
                    systemImage: "text.append",
                    isOn: viewModel.autoSkipCreditsBinding
                )
            } header: {
                Text("settings.playback.skipping.title")
            }

            Section {
                PlinxSettingsChoice(
                    Text("settings.playback.rewind"),
                    systemImage: "gobackward",
                    selection: viewModel.rewindBinding,
                    options: viewModel.seekOptions
                ) { seconds in
                    Text("settings.playback.seconds \(seconds)")
                }

                PlinxSettingsChoice(
                    Text("settings.playback.fastForward"),
                    systemImage: "goforward",
                    selection: viewModel.fastForwardBinding,
                    options: viewModel.seekOptions
                ) { seconds in
                    Text("settings.playback.seconds \(seconds)")
                }

                #if !os(tvOS)
                PlinxSettingsToggle(
                    Text("settings.playback.doubleTapToSeek"),
                    systemImage: "hand.tap.fill",
                    isOn: viewModel.doubleTapToSeekBinding,
                    description: Text("settings.playback.doubleTapToSeek.description")
                )
                #endif
            }

            #if !os(tvOS)
            Section {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    PlinxSettingsToggle(
                        Text("settings.playback.autoRotateVideo"),
                        systemImage: "rotate.right",
                        isOn: viewModel.autoRotateVideoBinding,
                        description: Text("settings.playback.autoRotateVideo.description")
                    )
                }
                PlinxSettingsToggle(
                    Text("settings.playback.pictureInPicture"),
                    systemImage: "pip",
                    isOn: viewModel.pictureInPictureBinding,
                    description: Text("settings.playback.pictureInPicture.description")
                )
                PlinxSettingsToggle(
                    Text("settings.playback.backgroundAudio"),
                    systemImage: "speaker.wave.2.bubble.fill",
                    isOn: viewModel.backgroundAudioBinding,
                    description: Text("settings.playback.backgroundAudio.description")
                )
            } footer: {
                Text(verbatim: PlinxSettingsCopy.playbackOutsideAppFooter)
            }
            #endif

            Section {
                PlinxSettingsToggle(
                    Text("settings.playback.showChaptersOnTimeline"),
                    isOn: viewModel.showChaptersOnTimelineBinding
                )
                PlinxSettingsToggle(
                    Text("settings.playback.showSkipSegmentsOnTimeline"),
                    isOn: viewModel.showSkipSegmentsOnTimelineBinding
                )
                PlinxSettingsToggle(
                    Text("settings.playback.showEndsAtTime"),
                    isOn: viewModel.showEndsAtTimeBinding
                )
                PlinxSettingsToggle(
                    Text("settings.playback.scrubThumbnails"),
                    isOn: viewModel.showScrubThumbnailPreviewsBinding,
                    description: Text("settings.playback.scrubThumbnails.description")
                )
            } header: {
                Text("settings.playback.timeline.title")
            }

            Section {
                PlinxSettingsChoice(
                    Text("settings.playback.quality"),
                    systemImage: "dial.medium.fill",
                    selection: viewModel.qualityPresetBinding,
                    options: TranscodeQualityPreset.displayOrder
                ) { preset in
                    Text(verbatim: preset.title)
                }
            } footer: {
                Text("settings.playback.quality.footer")
            }

            Section {
                PlinxSettingsChoice(
                    Text("settings.playback.readAhead"),
                    systemImage: "arrow.down.to.line",
                    selection: viewModel.readAheadBinding,
                    options: PlaybackReadAhead.allCases
                ) { option in
                    Text(verbatim: option.title)
                }
            } footer: {
                Text("settings.playback.readAhead.footer")
            }
        }
        .plinxSettingsListPage(title: Text("settings.playback.title"))
        .accessibilityIdentifier("settings.playback.screen")
    }
}

extension PlinxSettingsCopy {
    /// Footer under the Picture in Picture and background audio toggles.
    static var playbackOutsideAppFooter: String {
        String(
            localized: "settings.playback.plinx.outsideApp.footer",
            defaultValue: "Picture in Picture and background audio are off until you turn them on. While both are off, leaving Plinx closes the player, and the video picks up where it left off when you come back.",
            table: "Plinx"
        )
    }
}

@MainActor
struct PlinxAudioSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        let viewModel = SettingsViewModel(settingsManager: settingsManager)

        List {
            Section {
                PlinxSettingsToggle(
                    Text("settings.playback.nightMode"),
                    systemImage: "moon.fill",
                    isOn: viewModel.nightModeBinding,
                    description: Text("settings.playback.nightMode.footer")
                )

                PlinxSettingsChoice(
                    Text("settings.playback.dialogueBoost"),
                    systemImage: "person.wave.2.fill",
                    selection: viewModel.dialogueBoostBinding,
                    options: DialogueBoost.allCases
                ) { boost in
                    Text(verbatim: boost.title)
                }
            } header: {
                Text("settings.playback.audioEnhancements")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings.playback.dialogueBoost.footer")
                    Text("settings.playback.audioEnhancements.footer")
                }
            }

            Section {
                PlinxSettingsToggle(
                    Text("settings.playback.rememberTrackSelections"),
                    isOn: viewModel.rememberTrackSelectionsBinding,
                    description: Text("settings.playback.rememberTrackSelections.footer")
                )
                PlinxSettingsToggle(
                    Text("settings.playback.losslessAudio"),
                    isOn: viewModel.losslessAudioBinding,
                    description: Text("settings.playback.losslessAudio.footer")
                )
                if viewModel.isSpatialAudioAvailable {
                    PlinxSettingsToggle(
                        Text("settings.playback.spatialAudio"),
                        isOn: viewModel.spatialAudioBinding,
                        description: Text("settings.playback.spatialAudio.footer")
                    )
                }
            } header: {
                Text("settings.playback.audio.title")
            }

            #if !os(tvOS)
            // The offset steppers bring their own focus layout on Apple TV,
            // which the Plinx Settings list does not host.
            Section {
                AudioDelaySettingsRow()
            } footer: {
                Text("settings.playback.audioDelay.footer")
            }
            #endif
        }
        .plinxSettingsListPage(title: Text("settings.playback.audio.title"))
        .accessibilityIdentifier("settings.audio.screen")
    }
}

@MainActor
struct PlinxSubtitleSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        let viewModel = SettingsViewModel(settingsManager: settingsManager)

        List {
            Section {
                SubtitleAppearancePreview(appearance: settingsManager.playback.subtitleAppearance)
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("settings.playback.subtitles.preview.title")
            }

            Section {
                PlinxSettingsChoice(
                    Text("settings.playback.subtitleFontSize"),
                    selection: viewModel.subtitleFontSizeBinding,
                    options: viewModel.subtitleFontSizeOptions
                ) { fontSize in
                    Text("settings.playback.fontSize \(fontSize)")
                }
                PlinxSettingsChoice(
                    Text("settings.playback.subtitles.color"),
                    selection: viewModel.subtitleTextColorBinding,
                    options: viewModel.subtitleTextColorOptions
                ) { color in
                    Text(color.localizedName)
                }
                PlinxSettingsChoice(
                    Text("settings.playback.subtitles.weight"),
                    selection: viewModel.subtitleFontWeightBinding,
                    options: viewModel.subtitleFontWeightOptions
                ) { weight in
                    Text(weight.localizedName)
                }
                PlinxSettingsChoice(
                    Text("settings.playback.subtitles.background"),
                    selection: viewModel.subtitleBackgroundStrengthBinding,
                    options: viewModel.subtitleBackgroundStrengthOptions
                ) { strength in
                    Text(strength.localizedName)
                }
                PlinxSettingsChoice(
                    Text("settings.playback.subtitles.edge"),
                    selection: viewModel.subtitleEdgeStyleBinding,
                    options: viewModel.subtitleEdgeStyleOptions
                ) { style in
                    Text(style.localizedName)
                }
                PlinxSettingsChoice(
                    Text("settings.playback.subtitles.position"),
                    selection: viewModel.subtitleVerticalPositionBinding,
                    options: viewModel.subtitleVerticalPositionOptions
                ) { position in
                    Text(position.localizedName)
                }
            } footer: {
                Text("settings.playback.subtitles.footer")
            }

            if viewModel.showsSubtitleBottomMargin {
                Section {
                    PlinxSettingsChoice(
                        Text("settings.playback.subtitles.bottomMargin"),
                        selection: viewModel.subtitleBottomMarginBinding,
                        options: viewModel.subtitleBottomMarginOptions
                    ) { margin in
                        Text(margin.localizedName)
                    }
                } footer: {
                    Text("settings.playback.subtitles.bottomMargin.description")
                }
            }

            Section {
                PlinxSettingsChoice(
                    Text("settings.playback.subtitles.brightness"),
                    selection: viewModel.subtitleBrightnessBinding,
                    options: viewModel.subtitleBrightnessOptions
                ) { brightness in
                    Text(brightness.localizedName)
                }
            } footer: {
                Text("settings.playback.subtitles.brightness.description")
            }

            Section {
                PlinxSettingsToggle(
                    Text("settings.playback.subtitles.styledASS"),
                    isOn: viewModel.styledASSSubtitlesBinding,
                    description: Text("settings.playback.subtitles.styledASS.description")
                )
                PlinxSettingsToggle(
                    Text("settings.playback.subtitles.showOnSkipBack"),
                    isOn: viewModel.showSubtitlesOnSkipBackBinding,
                    description: Text("settings.playback.subtitles.showOnSkipBack.description")
                )
            }

            Section {
                Button("settings.playback.subtitles.reset", role: .destructive) {
                    viewModel.resetSubtitleAppearance()
                }
                #if os(tvOS)
                .plinxSettingsListButton()
                #endif
            }
        }
        .plinxSettingsListPage(title: Text("settings.playback.subtitles.title"))
        .accessibilityIdentifier("settings.subtitles.screen")
    }
}

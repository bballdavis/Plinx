import SwiftUI
import PlinxCore
import PlinxUI

/// The Plinx settings screen, protected by a parental gate.
struct PlinxSettingsView: View {
    @State private var isUnlocked = false

    var body: some View {
        if isUnlocked {
            settingsContent
        } else {
            ParentalGateView {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isUnlocked = true
                }
            }
        }
    }

    private var settingsContent: some View {
        SettingsBody()
    }
}

// MARK: - Settings body

private struct SettingsBody: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext

    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false
    @AppStorage("plinx.maxMovieRating") private var maxMovieRatingRaw = PlinxRating.pg.rawValue
    @AppStorage("plinx.maxTVRating")    private var maxTVRatingRaw    = PlinxRating.tvPg.rawValue
    @AppStorage("plinx.excludeUnrated") private var excludeUnrated    = true
    @AppStorage("plinx.pauseWhenScreenTurnsOff") private var pauseWhenScreenTurnsOff = true
    @AppStorage(PlinxNavigationPreference.showSearchInMainNavigationStorageKey)
    private var showSearchInMainNavigation = PlinxNavigationPreference.defaultShowSearchInMainNavigation

    @State private var isPresentingProfileSwitcher = false

    private var maxVolumeBinding: Binding<Double> {
        Binding(
            get: { Double(settingsManager.playback.maxVolumePercent) },
            set: { settingsManager.setMaxVolumePercent(Int($0.rounded())) }
        )
    }

    var body: some View {
        List {
            // MARK: Content subpages
            Section {
                NavigationLink(destination: VisibleLibrariesView()) {
                    Label {
                        Text("settings.libraries.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "square.grid.2x2.fill")
                    }
                }
                NavigationLink(destination: HomeScreenSettingsView()) {
                    Label {
                        Text("settings.homescreen.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "house.fill")
                    }
                }
                NavigationLink(destination: LibraryViewsSettingsView()) {
                    Label {
                        Text("Library Views")
                    } icon: {
                        Image(systemName: "rectangle.3.group.fill")
                    }
                }
                NavigationLink(
                    destination: DefaultServerSettingsView(
                        viewModel: ServerSelectionViewModel(
                            sessionManager: sessionManager,
                            context: plexApiContext
                        )
                    )
                ) {
                    Label {
                        Text("Default Server")
                    } icon: {
                        Image(systemName: "server.rack")
                    }
                }
                Toggle(isOn: $showSearchInMainNavigation) {
                    Label {
                        Text("settings.navigation.showSearchInMainNavigation", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            } header: {
                Text("settings.content.section", tableName: "Plinx")
            }

            // MARK: Appearance
            Section {
                NavigationLink(destination: AppearanceSettingsView()) {
                    Label {
                        Text("settings.appearance.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } header: {
                Text("settings.appearance.section", tableName: "Plinx")
            }

            // MARK: Downloads
            Section {
                NavigationLink(destination: SettingsDownloadsView()) {
                    Label {
                        Text("settings.downloads.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                }
            } header: {
                Text("settings.downloads.title", tableName: "Plinx")
            }

            // MARK: Playback
            Section {
                Toggle(isOn: $pauseWhenScreenTurnsOff) {
                    Label {
                        Text("settings.playback.pauseWhenScreenTurnsOff.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "pause.circle.fill")
                    }
                }
            } header: {
                Text("settings.playback.section", tableName: "Plinx")
            }

            // MARK: Content rating — movie
            Section {
                Picker(selection: $maxMovieRatingRaw) {
                    ForEach(PlinxRating.movieRatings, id: \.rawValue) { rating in
                        Text(rating.rawValue).tag(rating.rawValue)
                    }
                } label: {
                    Text("settings.safety.movie.rating.title", tableName: "Plinx")
                }
                .pickerStyle(.menu)

                Picker(selection: $maxTVRatingRaw) {
                    ForEach(PlinxRating.tvRatings, id: \.rawValue) { rating in
                        Text(rating.rawValue).tag(rating.rawValue)
                    }
                } label: {
                    Text("settings.safety.tv.rating.title", tableName: "Plinx")
                }
                .pickerStyle(.menu)

                Toggle(isOn: $excludeUnrated) {
                    Label {
                        Text("settings.safety.excludeUnrated.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "nosign")
                    }
                }
            } header: {
                Text("settings.safety.title", tableName: "Plinx")
            } footer: {
                Text("settings.safety.excludeUnrated.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Label {
                            Text("settings.safety.maxVolume.title", tableName: "Plinx")
                        } icon: {
                            Image(systemName: "speaker.wave.2.fill")
                        }

                        Spacer()

                        Text("\(settingsManager.playback.maxVolumePercent)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: maxVolumeBinding, in: 0...100, step: 5)
                }
                .padding(.vertical, 4)
            } header: {
                Text("settings.safety.audio.section", tableName: "Plinx")
            } footer: {
                Text("settings.safety.maxVolume.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Baby lock
            Section {
                Toggle(isOn: $babyLockEnabled) {
                    Label {
                        Text("settings.safety.touchlock.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                }
                NavigationLink(destination: SetPinView()) {
                    Label {
                        Text("Set Parental PIN", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "key.fill")
                    }
                }
            } header: {
                Text("settings.safety.touchlock.section", tableName: "Plinx")
            } footer: {
                Text("settings.safety.touchlock.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Account (profile switching)
            Section {
                Button {
                    isPresentingProfileSwitcher = true
                } label: {
                    Label {
                        Text("settings.profile.switch", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "person.2.fill")
                    }
                }
            } header: {
                Text("settings.profile.section", tableName: "Plinx")
            }

            // MARK: GPL compliance (hidden behind gate)
            Section {
                Link(destination: URL(string: "https://github.com/wunax/strimr")!) {
                    Label {
                        Text("settings.about.strimr", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
                .foregroundStyle(.primary)

                Link(destination: URL(string: "https://github.com/bballdavis/Plinx")!) {
                    Label {
                        Text("settings.about.plinx", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("settings.about.title", tableName: "Plinx")
            } footer: {
                Text("settings.about.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Session
            Section {
                Button(role: .destructive) {
                    Task { await sessionManager.signOut() }
                } label: {
                    Label("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle(Text("tabs.settings", tableName: "Plinx"))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
        }
        .sheet(isPresented: $isPresentingProfileSwitcher) {
            NavigationStack {
                ProfileSwitcherView(
                    viewModel: ProfileSwitcherViewModel(
                        context: plexApiContext,
                        sessionManager: sessionManager
                    )
                )
            }
        }
    }
}

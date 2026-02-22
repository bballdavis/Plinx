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

    @State private var isPresentingProfileSwitcher = false

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
            } header: {
                Label {
                    Text("settings.content.section", tableName: "Plinx")
                } icon: {
                    Image(systemName: "rectangle.stack.fill")
                }
            }

            // MARK: Appearance
            Section {
                NavigationLink(destination: AccentColorSettingsView()) {
                    Label {
                        Text("settings.accent.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "paintpalette.fill")
                    }
                }
            } header: {
                Label {
                    Text("settings.accent.section", tableName: "Plinx")
                } icon: {
                    Image(systemName: "paintbrush.fill")
                }
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
            } header: {
                Label {
                    Text("settings.safety.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "shield.fill")
                }
            } footer: {
                Text("settings.safety.rating.dual.description", tableName: "Plinx")
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
            } header: {
                Label {
                    Text("settings.safety.touchlock.section", tableName: "Plinx")
                } icon: {
                    Image(systemName: "hand.raised.fill")
                }
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
                Label {
                    Text("settings.profile.section", tableName: "Plinx")
                } icon: {
                    Image(systemName: "person.crop.circle.fill")
                }
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
            } header: {
                Label {
                    Text("settings.about.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "scroll.fill")
                }
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
        .background(Color.black.ignoresSafeArea())
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


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

    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false
    @AppStorage("plinx.maxRating") private var maxRatingRaw = PlinxRating.g.rawValue

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
                        Text("Home Screen")
                    } icon: {
                        Image(systemName: "house.fill")
                    }
                }
            } header: {
                Label {
                    Text("Content")
                } icon: {
                    Image(systemName: "rectangle.stack.fill")
                }
            }

            // MARK: Content rating
            Section {
                Picker(selection: $maxRatingRaw) {
                    ForEach(PlinxRating.allCases, id: \.rawValue) { rating in
                        Text(rating.rawValue).tag(rating.rawValue)
                    }
                } label: {
                    Text("settings.safety.rating.title", tableName: "Plinx")
                }
                .pickerStyle(.menu)
                .tint(.orange)
            } header: {
                Label {
                    Text("settings.safety.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "shield.fill")
                }
            } footer: {
                Text("settings.safety.rating.description", tableName: "Plinx")
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
                .tint(.orange)
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
    }
}

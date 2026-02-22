import SwiftUI
import PlinxCore
import PlinxUI

/// The Plinx settings screen, protected by a Plinxie-themed parental gate.
///
/// Access is gated behind `ParentalGateView` (MathGate multiplication challenge).
/// On unlock the gate stays open for the current session (`isUnlocked` is transient).
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

    // MARK: - Actual settings (shown post-gate)

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

    private var maxRating: PlinxRating {
        PlinxRating(rawValue: maxRatingRaw) ?? .g
    }

    var body: some View {
        List {
            // MARK: Libraries section
            Section {
                ForEach(libraryStore.libraries) { library in
                    LibraryToggleRow(library: library, settingsManager: settingsManager)
                }
            } header: {
                Label {
                    Text("settings.libraries.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "square.grid.2x2.fill")
                }
            } footer: {
                Text("settings.libraries.description", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            // MARK: GPL compliance (hidden behind this gate)
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

// MARK: - Library toggle row

private struct LibraryToggleRow: View {
    let library: Library
    let settingsManager: SettingsManager

    private var isVisible: Bool {
        !settingsManager.interface.hiddenLibraryIds.contains(library.id)
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isVisible },
            set: { show in
                if show {
                    settingsManager.setLibraryDisplayed(library.id, displayed: true)
                } else {
                    settingsManager.setLibraryDisplayed(library.id, displayed: false)
                }
            }
        )) {
            Label(library.title, systemImage: library.iconName)
        }
        .tint(.orange)
    }
}

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
                Label("Visible Libraries", systemImage: "square.grid.2x2.fill")
            } footer: {
                Text("Only selected libraries appear in the Plinx home and library screens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Content rating
            Section {
                Picker("Maximum Rating", selection: $maxRatingRaw) {
                    ForEach(PlinxRating.allCases, id: \.rawValue) { rating in
                        Text(rating.rawValue).tag(rating.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(.orange)
            } header: {
                Label("Content Safety", systemImage: "shield.fill")
            } footer: {
                Text("Content rated above this level won't appear anywhere in Plinx.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Baby lock
            Section {
                Toggle(isOn: $babyLockEnabled) {
                    Label("Baby Lock", systemImage: "lock.fill")
                }
                .tint(.orange)
            } header: {
                Label("Touch Protection", systemImage: "hand.raised.fill")
            } footer: {
                Text("When enabled, all touches are blocked until a triple-tap is detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: GPL compliance (hidden behind this gate)
            Section {
                Link(destination: URL(string: "https://github.com/wunax/strimr")!) {
                    Label("Strimr Open Source (GPL-2.0)", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .foregroundStyle(.primary)
            } header: {
                Label("Legal & Open Source", systemImage: "scroll.fill")
            } footer: {
                Text("Plinx is built on Strimr, licensed under the GPL-2.0. Source code is available at the link above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Session
            Section {
                Button(role: .destructive) {
                    Task { await sessionManager.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
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

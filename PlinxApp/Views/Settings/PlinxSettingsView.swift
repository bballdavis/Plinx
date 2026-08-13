import SwiftUI
import PlinxCore
import PlinxUI

/// The Plinx settings screen, protected by a parental gate.
struct PlinxSettingsView: View {
    @Environment(ParentalAccessCoordinator.self) private var parentalAccessCoordinator
    private let bypassGateForTesting: Bool
    private let contentFocusRequest: Int
    private let onRequestShellNavigationFocus: () -> Void

    init(
        isUnlocked: Bool = false,
        contentFocusRequest: Int = 0,
        onRequestShellNavigationFocus: @escaping () -> Void = {}
    ) {
        bypassGateForTesting = isUnlocked
        self.contentFocusRequest = contentFocusRequest
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
    }

    var body: some View {
        if bypassGateForTesting || parentalAccessCoordinator.isUnlocked {
            settingsContent
        } else {
            ParentalGateView(onAllowed: {})
        }
    }

    private var settingsContent: some View {
        SettingsBody(
            contentFocusRequest: contentFocusRequest,
            onRequestShellNavigationFocus: onRequestShellNavigationFocus
        )
    }
}

// MARK: - Settings body

private struct SettingsBody: View {
    let contentFocusRequest: Int
    let onRequestShellNavigationFocus: () -> Void

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext

    #if !os(tvOS)
    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false
    #endif
    @AppStorage("plinx.maxMovieRating") private var maxMovieRatingRaw = PlinxRating.g.rawValue
    @AppStorage("plinx.maxTVRating")    private var maxTVRatingRaw    = PlinxRating.tvY.rawValue
    @AppStorage("plinx.excludeUnrated") private var excludeUnrated    = true
    @AppStorage(PlinxNavigationPreference.showSearchInMainNavigationStorageKey)
    private var showSearchInMainNavigation = PlinxNavigationPreference.defaultShowSearchInMainNavigation

    @State private var isPresentingProfileSwitcher = false
    #if os(tvOS)
    @FocusState private var isFirstSettingFocused: Bool
    @State private var contentFocusGeneration = 0
    #endif

    private var maxVolumeBinding: Binding<Double> {
        Binding(
            get: { Double(settingsManager.playback.maxVolumePercent) },
            set: { settingsManager.setMaxVolumePercent(Int($0.rounded())) }
        )
    }

    var body: some View {
        #if os(tvOS)
        tvSettingsContent
        #else
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
                        Text("settings.libraryViews.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "rectangle.3.group.fill")
                    }
                }
                NavigationLink(destination: YoutarrSettingsView()) {
                    Label {
                        Text("youtarr.settings.title", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "sparkles.tv")
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
                        Text("settings.server.default.title", tableName: "Plinx")
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

            #if !os(tvOS)
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
            #endif

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
                        .accessibilityLabel(
                            Text("settings.safety.maxVolume.title", tableName: "Plinx")
                        )
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
                        Text("settings.parentalPIN.title", tableName: "Plinx")
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

                Link(destination: URL(string: "https://bballdavis.github.io/Plinx/docs/user/privacy-policy")!) {
                    Label {
                        Text("settings.about.privacy", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                    }
                }
                .foregroundStyle(.primary)

                Link(destination: URL(string: "https://github.com/bballdavis/Plinx/issues")!) {
                    Label {
                        Text("settings.about.support", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "questionmark.circle.fill")
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
        .plinxSettingsChrome(handlesExit: false)
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
        #endif
    }

    #if os(tvOS)
    private var tvSettingsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                TvSettingsSection(title: LocalizedStringKey("settings.content.section")) {
                    tvNavigationLink(
                        title: LocalizedStringKey("settings.libraries.title"),
                        icon: "square.grid.2x2.fill",
                        destination: VisibleLibrariesView()
                    )
                    .focused($isFirstSettingFocused)
                    .accessibilityIdentifier("settings.libraries")
                    .onMoveCommand { direction in
                        guard direction == .up else { return }
                        contentFocusGeneration &+= 1
                        onRequestShellNavigationFocus()
                    }
                    tvNavigationLink(
                        title: LocalizedStringKey("settings.homescreen.title"),
                        icon: "house.fill",
                        destination: HomeScreenSettingsView()
                    )
                    tvNavigationLink(
                        title: LocalizedStringKey("settings.libraryViews.title"),
                        icon: "rectangle.3.group.fill",
                        destination: LibraryViewsSettingsView()
                    )
                    tvNavigationLink(
                        title: LocalizedStringKey("youtarr.settings.title"),
                        icon: "sparkles.tv",
                        destination: YoutarrSettingsView()
                    )
                    .accessibilityIdentifier("settings.youtarr")
                    tvNavigationLink(
                        title: LocalizedStringKey("settings.server.default.title"),
                        icon: "server.rack",
                        destination: DefaultServerSettingsView(
                            viewModel: ServerSelectionViewModel(
                                sessionManager: sessionManager,
                                context: plexApiContext
                            )
                        )
                    )
                    TvSettingsToggleRow(
                        title: LocalizedStringKey("settings.navigation.showSearchInMainNavigation"),
                        icon: "magnifyingglass",
                        isOn: $showSearchInMainNavigation
                    )
                }

                TvSettingsSection(title: LocalizedStringKey("settings.appearance.section")) {
                    tvNavigationLink(
                        title: LocalizedStringKey("settings.appearance.title"),
                        icon: "paintpalette.fill",
                        destination: AppearanceSettingsView()
                    )
                }

                TvSettingsSection(
                    title: LocalizedStringKey("settings.safety.title"),
                    footer: LocalizedStringKey("settings.safety.excludeUnrated.description")
                ) {
                    NavigationLink {
                        TvRatingChooser(
                            title: LocalizedStringKey("settings.safety.movie.rating.title"),
                            ratings: PlinxRating.movieRatings.map(\.rawValue),
                            selection: $maxMovieRatingRaw
                        )
                    } label: {
                        TvSettingsRow(
                            title: LocalizedStringKey("settings.safety.movie.rating.title"),
                            icon: "film.fill",
                            trailingValue: maxMovieRatingRaw,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityIdentifier("settings.rating.movie")

                    NavigationLink {
                        TvRatingChooser(
                            title: LocalizedStringKey("settings.safety.tv.rating.title"),
                            ratings: PlinxRating.tvRatings.map(\.rawValue),
                            selection: $maxTVRatingRaw
                        )
                    } label: {
                        TvSettingsRow(
                            title: LocalizedStringKey("settings.safety.tv.rating.title"),
                            icon: "tv.fill",
                            trailingValue: maxTVRatingRaw,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityIdentifier("settings.rating.tv")

                    TvSettingsToggleRow(
                        title: LocalizedStringKey("settings.safety.excludeUnrated.title"),
                        icon: "nosign",
                        isOn: $excludeUnrated
                    )
                }

                TvSettingsSection(
                    title: LocalizedStringKey("settings.safety.audio.section"),
                    footer: LocalizedStringKey("settings.safety.maxVolume.description")
                ) {
                    TvVolumeSettingsRow(
                        value: settingsManager.playback.maxVolumePercent,
                        onDecrease: {
                            settingsManager.setMaxVolumePercent(
                                max(settingsManager.playback.maxVolumePercent - 5, 0)
                            )
                        },
                        onIncrease: {
                            settingsManager.setMaxVolumePercent(
                                min(settingsManager.playback.maxVolumePercent + 5, 100)
                            )
                        }
                    )
                }

                TvSettingsSection(title: LocalizedStringKey("settings.parentalPIN.title")) {
                    tvNavigationLink(
                        title: LocalizedStringKey("settings.parentalPIN.title"),
                        icon: "key.fill",
                        destination: SetPinView()
                    )
                    .accessibilityIdentifier("settings.parentalPIN")
                }

                TvSettingsSection(title: LocalizedStringKey("settings.profile.section")) {
                    Button {
                        isPresentingProfileSwitcher = true
                    } label: {
                        TvSettingsRow(
                            title: LocalizedStringKey("settings.profile.switch"),
                            icon: "person.2.fill",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                }

                TvSettingsSection(
                    title: LocalizedStringKey("settings.about.title"),
                    footer: LocalizedStringKey("settings.about.description")
                ) {
                    tvExternalLink(
                        title: LocalizedStringKey("settings.about.strimr"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        url: URL(string: "https://github.com/wunax/strimr")!
                    )
                    tvExternalLink(
                        title: LocalizedStringKey("settings.about.plinx"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        url: URL(string: "https://github.com/bballdavis/Plinx")!
                    )
                    tvExternalLink(
                        title: LocalizedStringKey("settings.about.privacy"),
                        icon: "hand.raised.fill",
                        url: URL(string: "https://bballdavis.github.io/Plinx/docs/user/privacy-policy")!
                    )
                    tvExternalLink(
                        title: LocalizedStringKey("settings.about.support"),
                        icon: "questionmark.circle.fill",
                        url: URL(string: "https://github.com/bballdavis/Plinx/issues")!
                    )
                }

                TvSettingsSection(title: LocalizedStringKey("common.actions.logOut")) {
                    Button(role: .destructive) {
                        Task { await sessionManager.signOut() }
                    } label: {
                        TvSettingsRow(
                            title: LocalizedStringKey("common.actions.logOut"),
                            icon: "rectangle.portrait.and.arrow.right",
                            roleColor: .red
                        )
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                }
            }
            .padding(.horizontal, 42)
            .padding(.top, 10)
            .padding(.bottom, 50)
        }
        .background(Color.appBackground)
        .plinxSettingsChrome(handlesExit: false)
        .task {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
        }
        .onChange(of: contentFocusRequest) { _, _ in
            contentFocusGeneration &+= 1
            let generation = contentFocusGeneration
            isFirstSettingFocused = false
            Task { @MainActor in
                await Task.yield()
                guard generation == contentFocusGeneration else { return }
                isFirstSettingFocused = true
            }
        }
        .onAppear {
            isFirstSettingFocused = true
        }
        .sheet(isPresented: $isPresentingProfileSwitcher) {
            NavigationStack {
                PlinxProfileSwitcherTVView(
                    viewModel: ProfileSwitcherViewModel(
                        context: plexApiContext,
                        sessionManager: sessionManager
                    )
                )
            }
        }
    }

    private func tvNavigationLink<Destination: View>(
        title: LocalizedStringKey,
        icon: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            TvSettingsRow(title: title, icon: icon, showsChevron: true)
        }
        .buttonStyle(PlinkButtonStyle())
        .focusEffectDisabled()
    }

    private func tvExternalLink(
        title: LocalizedStringKey,
        icon: String,
        url: URL
    ) -> some View {
        Link(destination: url) {
            TvSettingsRow(title: title, icon: icon, showsChevron: true)
        }
        .buttonStyle(PlinkButtonStyle())
        .focusEffectDisabled()
    }
    #endif
}

#if os(tvOS)
private struct TvSettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title, tableName: "Plinx")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.leading, 18)

            VStack(spacing: 12) {
                content()
            }

            if let footer {
                Text(footer, tableName: "Plinx")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(.horizontal, 18)
            }
        }
    }
}

private struct TvSettingsRow: View {
    let title: LocalizedStringKey
    let icon: String
    var trailingValue: String?
    var showsChevron = false
    var roleColor: Color = .white

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isFocused ? .white : roleColor)
                .frame(width: 42)

            Text(title, tableName: "Plinx")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 20)

            if let trailingValue {
                Text(trailingValue)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 78)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .plinxFocusSurface(
            isSelected: false,
            isFocused: isFocused,
            style: .tvSettings(cornerRadius: 18)
        )
    }
}

private struct TvSettingsToggleRow: View {
    let title: LocalizedStringKey
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        let localizedValue = String(
            localized: isOn ? "common.status.on" : "common.status.off",
            table: "Plinx"
        )

        Button {
            isOn.toggle()
        } label: {
            TvSettingsRow(
                title: title,
                icon: icon,
                trailingValue: localizedValue
            )
        }
        .buttonStyle(PlinkButtonStyle())
        .focusEffectDisabled()
        .accessibilityValue(localizedValue)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct TvVolumeSettingsRow: View {
    let value: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            TvSettingsRow(
                title: LocalizedStringKey("settings.safety.maxVolume.title"),
                icon: "speaker.wave.2.fill",
                trailingValue: "\(value)%"
            )

            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 72, height: 64)
            }
            .buttonStyle(TvSettingsAdjustmentButtonStyle())
            .focusEffectDisabled()
            .accessibilityLabel(Text("settings.safety.maxVolume.decrease", tableName: "Plinx"))

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 72, height: 64)
            }
            .buttonStyle(TvSettingsAdjustmentButtonStyle())
            .focusEffectDisabled()
            .accessibilityLabel(Text("settings.safety.maxVolume.increase", tableName: "Plinx"))
        }
        .padding(.trailing, 14)
    }
}

private struct TvSettingsAdjustmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TvSettingsAdjustmentButtonBody(configuration: configuration)
    }
}

private struct TvSettingsAdjustmentButtonBody: View {
    let configuration: TvSettingsAdjustmentButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .plinxFocusSurface(
                isSelected: false,
                isFocused: isFocused,
                style: .tvSettings(cornerRadius: 18)
            )
    }
}

private struct TvRatingChooser: View {
    let title: LocalizedStringKey
    let ratings: [String]
    @Binding var selection: String
    @FocusState private var focusedRating: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text(title, tableName: "Plinx")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)

                ForEach(ratings, id: \.self) { rating in
                    Button {
                        selection = rating
                    } label: {
                        TvRatingChoiceRow(rating: rating, isSelected: selection == rating)
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedRating, equals: rating)
                    .accessibilityIdentifier("settings.rating.choice.\(rating)")
                }
            }
            .padding(42)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .accessibilityIdentifier("settings.rating.screen")
        .plinxSettingsChrome()
        .onAppear {
            focusedRating = ratings.contains(selection) ? selection : ratings.first
        }
    }
}

private struct TvRatingChoiceRow: View {
    let rating: String
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack {
            Text(rating)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 76)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.07)))
        .plinxFocusSurface(
            isSelected: isSelected,
            isFocused: isFocused,
            style: .tvSettings(cornerRadius: 20)
        )
    }
}
#endif

import PlinxCore
import PlinxUI
import SwiftUI

/// The Plinx settings screen, protected by a parental gate.
///
/// Everything here is parent-only: content ratings, library visibility, the
/// player, accounts and servers, profiles, legal notices and Log Out. Upstream
/// Settings shells (`SettingsView`, the tvOS settings columns) are not used, so
/// playback speed, external players, trackers and Seerr integrations never
/// appear.
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
    @Environment(ParentalAccessCoordinator.self) private var parentalAccessCoordinator

    #if !os(tvOS)
    @Environment(DownloadManager.self) private var downloadManager
    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false
    #endif
    @AppStorage(PlinxSafetyPreferences.maxMovieRatingKey)
    private var maxMovieRatingRaw = PlinxSafetyPreferences.defaultMovieRating.rawValue
    @AppStorage(PlinxSafetyPreferences.maxTVRatingKey)
    private var maxTVRatingRaw = PlinxSafetyPreferences.defaultTVRating.rawValue
    @AppStorage(PlinxSafetyPreferences.excludeUnratedKey) private var excludeUnrated = true
    @AppStorage(PlinxNavigationPreference.showSearchInMainNavigationStorageKey)
    private var showSearchInMainNavigation = PlinxNavigationPreference.defaultShowSearchInMainNavigation

    @State private var isPresentingProfileSwitcher = false
    @State private var isConfirmingSignOut = false
    @State private var isSigningOut = false
    @State private var accessLease = PlinxSettingsAccessLease()
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

    private var youtarrConfigurationStore: YoutarrConfigurationStore {
        DemoFixtureBootstrap.isActive ? DemoPreferences.youtarrStore : YoutarrConfigurationStore()
    }

    var body: some View {
        platformContent
            .task {
                if libraryStore.libraries.isEmpty {
                    try? await libraryStore.loadLibraries()
                }
            }
            .sheet(isPresented: $isPresentingProfileSwitcher) {
                NavigationStack {
                    ProfileSwitcherView(
                        viewModel: ProfileSwitcherViewModel(sessionManager: sessionManager),
                        onClose: { isPresentingProfileSwitcher = false }
                    )
                }
            }
            .alert(
                Text("common.actions.logOut", tableName: "Plinx"),
                isPresented: $isConfirmingSignOut
            ) {
                Button(role: .destructive) {
                    signOut()
                } label: {
                    Text("common.actions.logOut", tableName: "Plinx")
                }
                Button("common.actions.cancel", role: .cancel) {}
            } message: {
                Text(verbatim: ProfileSwitcherView.logoutMessage)
            }
            .onAppear {
                accessLease.hold(parentalAccessCoordinator)
            }
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(tvOS)
        tvSettingsContent
        #else
        iOSSettingsContent
        #endif
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        Task {
            #if os(tvOS)
            await PlinxSignOut.signOut(
                sessionManager: sessionManager,
                parentalAccess: parentalAccessCoordinator
            )
            #else
            await PlinxSignOut.signOut(
                sessionManager: sessionManager,
                downloadManager: downloadManager,
                parentalAccess: parentalAccessCoordinator
            )
            #endif
            isSigningOut = false
        }
    }

    // MARK: - iPhone and iPad

    #if !os(tvOS)
    private var iOSSettingsContent: some View {
        List {
            contentSection
            appearanceSection
            downloadsSection
            ratingSection
            audioSafetySection
            playerSection
            touchProtectionSection
            accountsSection
            legalSection
            signOutSection
        }
        .navigationTitle(Text("tabs.settings", tableName: "Plinx"))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .plinxSettingsChrome(handlesExit: false)
        .disabled(isSigningOut)
    }

    private var contentSection: some View {
        Section {
            NavigationLink(destination: VisibleLibrariesView()) {
                Label {
                    Text("settings.libraries.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "square.grid.2x2.fill")
                }
            }
            .accessibilityIdentifier("settings.libraries")
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
            NavigationLink(destination: YoutarrSettingsView(configurationStore: youtarrConfigurationStore)) {
                Label {
                    Text("youtarr.settings.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "sparkles.tv")
                }
            }
            .accessibilityIdentifier("settings.youtarr")
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
    }

    private var appearanceSection: some View {
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
    }

    private var downloadsSection: some View {
        Section {
            NavigationLink(destination: SettingsDownloadsView()) {
                Label {
                    Text("settings.downloads.title", tableName: "Plinx")
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
            }
            NavigationLink {
                SettingsStorageView()
                    .navigationBarTitleDisplayMode(.large)
                    .background(Color.appBackground.ignoresSafeArea())
                    .plinxSettingsChrome()
            } label: {
                Label {
                    Text("settings.storage.title")
                } icon: {
                    Image(systemName: "internaldrive.fill")
                }
            }
            .accessibilityIdentifier("settings.storage")
        } header: {
            Text("settings.downloads.title", tableName: "Plinx")
        }
    }

    private var ratingSection: some View {
        Section {
            Picker(selection: $maxMovieRatingRaw) {
                ForEach(PlinxRating.movieRatings, id: \.rawValue) { rating in
                    Text(rating.rawValue).tag(rating.rawValue)
                }
            } label: {
                Text("settings.safety.movie.rating.title", tableName: "Plinx")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.rating.movie")

            Picker(selection: $maxTVRatingRaw) {
                ForEach(PlinxRating.tvRatings, id: \.rawValue) { rating in
                    Text(rating.rawValue).tag(rating.rawValue)
                }
            } label: {
                Text("settings.safety.tv.rating.title", tableName: "Plinx")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.rating.tv")

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
    }

    private var audioSafetySection: some View {
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

                Slider(value: maxVolumeBinding, in: 0 ... 100, step: 5)
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
    }

    private var playerSection: some View {
        Section {
            NavigationLink(destination: PlinxPlaybackSettingsView()) {
                Label {
                    Text("settings.playback.title")
                } icon: {
                    Image(systemName: "play.rectangle.fill")
                }
            }
            .accessibilityIdentifier("settings.playback")
            NavigationLink(destination: PlinxAudioSettingsView()) {
                Label {
                    Text("settings.playback.audio.title")
                } icon: {
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
            .accessibilityIdentifier("settings.audio")
            NavigationLink(destination: PlinxSubtitleSettingsView()) {
                Label {
                    Text("settings.playback.subtitles.title")
                } icon: {
                    Image(systemName: "captions.bubble.fill")
                }
            }
            .accessibilityIdentifier("settings.subtitles")
        } header: {
            Text(verbatim: PlinxSettingsCopy.playerSection)
        } footer: {
            Text(verbatim: PlinxSettingsCopy.playerFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var touchProtectionSection: some View {
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
            .accessibilityIdentifier("settings.parentalPIN")
        } header: {
            Text("settings.safety.touchlock.section", tableName: "Plinx")
        } footer: {
            Text("settings.safety.touchlock.description", tableName: "Plinx")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accountsSection: some View {
        Section {
            NavigationLink(destination: PlinxAccountsSettingsView()) {
                Label {
                    Text("settings.accounts.title")
                } icon: {
                    Image(systemName: "server.rack")
                }
            }
            .accessibilityIdentifier("settings.accounts")

            Button {
                isPresentingProfileSwitcher = true
            } label: {
                Label {
                    Text("settings.profile.switch", tableName: "Plinx")
                } icon: {
                    Image(systemName: "person.2.fill")
                }
            }
            .accessibilityIdentifier("settings.profile.switch")
        } header: {
            Text(verbatim: PlinxSettingsCopy.accountsSection)
        } footer: {
            Group {
                if DemoFixtureBootstrap.isActive {
                    Text("settings.demo.profile", tableName: "Plinx")
                } else {
                    Text(verbatim: PlinxSettingsCopy.accountsFooter)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .disabled(DemoFixtureBootstrap.isActive)
    }

    private var legalSection: some View {
        Section {
            Link(destination: PlinxSettingsLinks.strimrSource) {
                Label {
                    Text("settings.about.strimr", tableName: "Plinx")
                } icon: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
            }
            .foregroundStyle(.primary)

            Link(destination: PlinxSettingsLinks.plinxSource) {
                Label {
                    Text("settings.about.plinx", tableName: "Plinx")
                } icon: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
            }
            .foregroundStyle(.primary)

            NavigationLink(destination: PlinxLicensesSettingsView()) {
                Label {
                    Text("settings.licenses.title")
                } icon: {
                    Image(systemName: "doc.text.fill")
                }
            }
            .accessibilityIdentifier("settings.licenses")

            Link(destination: PlinxSettingsLinks.privacyPolicy) {
                Label {
                    Text("settings.about.privacy", tableName: "Plinx")
                } icon: {
                    Image(systemName: "hand.raised.fill")
                }
            }
            .foregroundStyle(.primary)

            Link(destination: PlinxSettingsLinks.support) {
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
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingSignOut = true
            } label: {
                HStack {
                    Label {
                        Text("common.actions.logOut", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    if isSigningOut {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .accessibilityIdentifier("settings.logOut")
        }
    }
    #endif

    // MARK: - Apple TV

    #if os(tvOS)
    private var tvSettingsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                TvSettingsSection(title: plinxText("settings.content.section")) {
                    tvNavigationLink(
                        title: plinxText("settings.libraries.title"),
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
                        title: plinxText("settings.homescreen.title"),
                        icon: "house.fill",
                        destination: HomeScreenSettingsView()
                    )
                    tvNavigationLink(
                        title: plinxText("settings.libraryViews.title"),
                        icon: "rectangle.3.group.fill",
                        destination: LibraryViewsSettingsView()
                    )
                    tvNavigationLink(
                        title: plinxText("youtarr.settings.title"),
                        icon: "sparkles.tv",
                        destination: YoutarrSettingsView(configurationStore: youtarrConfigurationStore)
                    )
                    .accessibilityIdentifier("settings.youtarr")
                    TvSettingsToggleRow(
                        title: plinxText("settings.navigation.showSearchInMainNavigation"),
                        icon: "magnifyingglass",
                        isOn: $showSearchInMainNavigation
                    )
                }

                TvSettingsSection(title: plinxText("settings.appearance.section")) {
                    tvNavigationLink(
                        title: plinxText("settings.appearance.title"),
                        icon: "paintpalette.fill",
                        destination: AppearanceSettingsView()
                    )
                }

                TvSettingsSection(
                    title: plinxText("settings.safety.title"),
                    footer: plinxText("settings.safety.excludeUnrated.description")
                ) {
                    NavigationLink {
                        TvRatingChooser(
                            title: plinxText("settings.safety.movie.rating.title"),
                            ratings: PlinxRating.movieRatings.map(\.rawValue),
                            selection: $maxMovieRatingRaw
                        )
                    } label: {
                        TvSettingsRow(
                            title: plinxText("settings.safety.movie.rating.title"),
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
                            title: plinxText("settings.safety.tv.rating.title"),
                            ratings: PlinxRating.tvRatings.map(\.rawValue),
                            selection: $maxTVRatingRaw
                        )
                    } label: {
                        TvSettingsRow(
                            title: plinxText("settings.safety.tv.rating.title"),
                            icon: "tv.fill",
                            trailingValue: maxTVRatingRaw,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityIdentifier("settings.rating.tv")

                    TvSettingsToggleRow(
                        title: plinxText("settings.safety.excludeUnrated.title"),
                        icon: "nosign",
                        isOn: $excludeUnrated
                    )
                }

                TvSettingsSection(
                    title: plinxText("settings.safety.audio.section"),
                    footer: plinxText("settings.safety.maxVolume.description")
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

                TvSettingsSection(
                    title: Text(verbatim: PlinxSettingsCopy.playerSection),
                    footer: Text(verbatim: PlinxSettingsCopy.playerFooter)
                ) {
                    tvNavigationLink(
                        title: Text("settings.playback.title"),
                        icon: "play.rectangle.fill",
                        destination: PlinxPlaybackSettingsView()
                    )
                    .accessibilityIdentifier("settings.playback")
                    tvNavigationLink(
                        title: Text("settings.playback.audio.title"),
                        icon: "speaker.wave.3.fill",
                        destination: PlinxAudioSettingsView()
                    )
                    .accessibilityIdentifier("settings.audio")
                    tvNavigationLink(
                        title: Text("settings.playback.subtitles.title"),
                        icon: "captions.bubble.fill",
                        destination: PlinxSubtitleSettingsView()
                    )
                    .accessibilityIdentifier("settings.subtitles")
                }

                TvSettingsSection(title: plinxText("settings.parentalPIN.title")) {
                    tvNavigationLink(
                        title: plinxText("settings.parentalPIN.title"),
                        icon: "key.fill",
                        destination: SetPinView()
                    )
                    .accessibilityIdentifier("settings.parentalPIN")
                }

                TvSettingsSection(
                    title: Text(verbatim: PlinxSettingsCopy.accountsSection),
                    footer: DemoFixtureBootstrap.isActive
                        ? plinxText("settings.demo.profile")
                        : Text(verbatim: PlinxSettingsCopy.accountsFooter)
                ) {
                    tvNavigationLink(
                        title: Text("settings.accounts.title"),
                        icon: "server.rack",
                        destination: PlinxAccountsSettingsView()
                    )
                    .accessibilityIdentifier("settings.accounts")

                    Button {
                        isPresentingProfileSwitcher = true
                    } label: {
                        TvSettingsRow(
                            title: plinxText("settings.profile.switch"),
                            icon: "person.2.fill",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityIdentifier("settings.profile.switch")
                }
                .disabled(DemoFixtureBootstrap.isActive)

                TvSettingsSection(
                    title: plinxText("settings.about.title"),
                    footer: plinxText("settings.about.description")
                ) {
                    tvExternalLink(
                        title: plinxText("settings.about.strimr"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        url: PlinxSettingsLinks.strimrSource
                    )
                    tvExternalLink(
                        title: plinxText("settings.about.plinx"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        url: PlinxSettingsLinks.plinxSource
                    )
                    tvNavigationLink(
                        title: Text("settings.licenses.title"),
                        icon: "doc.text.fill",
                        destination: PlinxLicensesSettingsView()
                    )
                    .accessibilityIdentifier("settings.licenses")
                    tvExternalLink(
                        title: plinxText("settings.about.privacy"),
                        icon: "hand.raised.fill",
                        url: PlinxSettingsLinks.privacyPolicy
                    )
                    tvExternalLink(
                        title: plinxText("settings.about.support"),
                        icon: "questionmark.circle.fill",
                        url: PlinxSettingsLinks.support
                    )
                }

                TvSettingsSection(title: plinxText("common.actions.logOut")) {
                    Button(role: .destructive) {
                        isConfirmingSignOut = true
                    } label: {
                        TvSettingsRow(
                            title: plinxText("common.actions.logOut"),
                            icon: "rectangle.portrait.and.arrow.right",
                            roleColor: .red
                        )
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .focusEffectDisabled()
                    .disabled(isSigningOut)
                    .accessibilityIdentifier("settings.logOut")
                }
            }
            .padding(.horizontal, 42)
            .padding(.top, 10)
            .padding(.bottom, 50)
        }
        .background(Color.appBackground)
        .plinxSettingsChrome(handlesExit: false)
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
    }

    private func tvNavigationLink<Destination: View>(
        title: Text,
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
        title: Text,
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

// MARK: - Copy and links

/// Settings copy added with the multi-account port. English renders from the
/// default values until the strings table gains these keys.
enum PlinxSettingsCopy {
    static var accountsSection: String {
        String(
            localized: "settings.accounts.plinx.section",
            defaultValue: "Accounts and Profiles",
            table: "Plinx"
        )
    }

    static var accountsFooter: String {
        String(
            localized: "settings.accounts.plinx.footer",
            defaultValue: "Add a Plex account or a Jellyfin server and choose which servers this profile uses. Every server follows the same content ratings.",
            table: "Plinx"
        )
    }

    static var playerSection: String {
        String(localized: "settings.player.plinx.section", defaultValue: "Player", table: "Plinx")
    }

    static var playerFooter: String {
        String(
            localized: "settings.player.plinx.footer",
            defaultValue: "Videos always play in Plinx, at normal speed.",
            table: "Plinx"
        )
    }

    static var bedtimeSection: String {
        String(
            localized: "settings.playback.plinx.bedtime.section",
            defaultValue: "Bedtime and Autoplay",
            table: "Plinx"
        )
    }

    static var bedtimeFooter: String {
        String(
            localized: "settings.playback.plinx.bedtime.footer",
            defaultValue: "The sleep timer starts with every video and pauses playback when it runs out. Set Play next episode to Off to stop after each episode.",
            table: "Plinx"
        )
    }
}

/// Legal and support destinations, shown only inside parent-gated Settings.
enum PlinxSettingsLinks {
    static let strimrSource = URL(string: "https://github.com/wunax/strimr")!
    static let plinxSource = URL(string: "https://github.com/bballdavis/Plinx")!
    static let privacyPolicy = URL(string: "https://bballdavis.github.io/Plinx/docs/user/privacy-policy")!
    static let support = URL(string: "https://github.com/bballdavis/Plinx/issues")!
}

// MARK: - Apple TV rows

#if os(tvOS)
/// A Plinx-table string for the Apple TV rows below.
private func plinxText(_ key: LocalizedStringKey) -> Text {
    Text(key, tableName: "Plinx")
}

private struct TvSettingsSection<Content: View>: View {
    let title: Text
    var footer: Text?
    @ViewBuilder let content: () -> Content

    init(
        title: Text,
        footer: Text? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.leading, 18)

            VStack(spacing: 12) {
                content()
            }

            if let footer {
                footer
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(.horizontal, 18)
            }
        }
    }
}

private struct TvSettingsRow: View {
    let title: Text
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

            title
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
    let title: Text
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
                title: plinxText("settings.safety.maxVolume.title"),
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
    let title: Text
    let ratings: [String]
    @Binding var selection: String
    @FocusState private var focusedRating: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                title
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

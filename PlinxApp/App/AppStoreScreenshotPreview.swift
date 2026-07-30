import PlinxUI
import SwiftUI

/// Credential-free, fictional content used only for App Store and
/// documentation captures launched with `--ui-testing`.
enum AppStoreScreenshotPreview {
    static let splashScreen = "appStoreSplash"
    static let homeScreen = "appStoreHome"
    static let mediaDetailScreen = "appStoreMediaDetail"
    static let settingsScreen = "appStoreSettings"
    static let youtarrScreen = "appStoreYoutarr"
}

struct AppStoreSplashPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.04, green: 0.19, blue: 0.16)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()
                Image("BrandLockupWhite")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 310)

                VStack(spacing: 10) {
                    Text("Your family’s media, thoughtfully managed.")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Connect your Plex library and optional Youtarr service with parent-managed ratings and access.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: 420)
                }

                Button {} label: {
                    Text("Continue with Plex")
                        .font(.headline)
                        .frame(maxWidth: 360, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                HStack(spacing: 18) {
                    Label("Private by default", systemImage: "hand.raised.fill")
                    Label("Parent managed", systemImage: "lock.shield.fill")
                }
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.72))

                Spacer()
            }
            .padding(30)
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier("appStore.splash")
    }
}

struct AppStoreHomePreview: View {
    private let continueWatching = [
        StoreMediaFixture("Space Camp", "42 min left", "sparkles", [.indigo, .blue]),
        StoreMediaFixture("Kitchen Lab", "18 min left", "flask.fill", [.orange, .pink]),
        StoreMediaFixture("Wild Neighbors", "New episode", "pawprint.fill", [.green, .teal]),
    ]

    private let recentlyAdded = [
        StoreMediaFixture("Moonbound", "2026 · PG", "moon.stars.fill", [.blue, .purple]),
        StoreMediaFixture("The Big Build", "2025 · TV-PG", "hammer.fill", [.orange, .yellow]),
        StoreMediaFixture("Cloud Chasers", "2026 · PG", "cloud.sun.fill", [.cyan, .blue]),
        StoreMediaFixture("Hidden Gardens", "2024 · TV-G", "leaf.fill", [.green, .mint]),
        StoreMediaFixture("Robot Club", "2026 · TV-PG", "cpu.fill", [.purple, .pink]),
    ]

    private let youtarrVideos = [
        StoreMediaFixture("How Bridges Work", "Curious Workshop · TV-G", "building.columns.fill", [.teal, .blue]),
        StoreMediaFixture("Backyard Astronomy", "Sky Club · TV-PG", "telescope", [.indigo, .purple]),
        StoreMediaFixture("Make a Tiny Garden", "Green Things · TV-G", "camera.macro", [.green, .yellow]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    StoreScreenshotHeader()
                    StoreMediaRail(title: "Continue Watching", fixtures: continueWatching, landscape: true)
                    StoreMediaRail(title: "Recently Added Movies & TV", fixtures: recentlyAdded, landscape: false)
                    StoreMediaRail(title: "Explore from Youtarr", fixtures: youtarrVideos, landscape: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                StoreTabBar(selected: "Home")
            }
        }
        .accessibilityIdentifier("appStore.home")
    }
}

struct AppStoreMediaDetailPreview: View {
    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > 700

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.indigo, .blue.opacity(0.8), .black],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                        .frame(height: isWide ? 520 : 390)
                        .overlay {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: isWide ? 180 : 110, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 14) {
                            Text("MOONBOUND")
                                .font(.system(size: isWide ? 64 : 42, weight: .black, design: .rounded))
                            Text("A family science adventure")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        .padding(isWide ? 42 : 24)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        Button {} label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        HStack(spacing: 10) {
                            StoreMetadataPill("2026")
                            StoreMetadataPill("1h 42m")
                            StoreMetadataPill("PG")
                            StoreMetadataPill("4K")
                        }

                        Text("A curious crew builds a backyard observatory and discovers that the biggest adventures can begin close to home.")
                            .font(isWide ? .title3 : .body)
                            .foregroundStyle(.white.opacity(0.82))

                        Text("More like this")
                            .font(.title2.bold())

                        StoreMediaRail(
                            title: "",
                            fixtures: [
                                StoreMediaFixture("Cloud Chasers", "PG", "cloud.sun.fill", [.cyan, .blue]),
                                StoreMediaFixture("Robot Club", "TV-PG", "cpu.fill", [.purple, .pink]),
                                StoreMediaFixture("The Big Build", "TV-PG", "hammer.fill", [.orange, .yellow]),
                            ],
                            landscape: true
                        )
                    }
                    .padding(.horizontal, isWide ? 42 : 20)
                    .padding(.bottom, 48)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier("appStore.mediaDetail")
    }
}

struct AppStoreYoutarrPreview: View {
    private let videos = [
        StoreMediaFixture("How Bridges Work", "Curious Workshop · TV-G", "building.columns.fill", [.teal, .blue]),
        StoreMediaFixture("Backyard Astronomy", "Sky Club · TV-PG", "telescope", [.indigo, .purple]),
        StoreMediaFixture("Make a Tiny Garden", "Green Things · TV-G", "camera.macro", [.green, .yellow]),
        StoreMediaFixture("The Science of Sound", "Everyday Lab · TV-PG", "waveform", [.orange, .pink]),
        StoreMediaFixture("Drawing Friendly Dragons", "Art Table · TV-Y7", "paintbrush.fill", [.purple, .blue]),
        StoreMediaFixture("Build a Bird Feeder", "Curious Workshop · TV-G", "bird.fill", [.green, .teal]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Explore")
                                .font(.largeTitle.bold())
                            Text("Parent-approved videos from Youtarr")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image("BrandMarkColor")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                    }

                    StoreMediaRail(
                        title: "Newest videos",
                        fixtures: Array(videos.prefix(3)),
                        landscape: true
                    )

                    Text("Channels")
                        .font(.title2.bold())
                    HStack(spacing: 12) {
                        StoreChannelPill("Curious Workshop", "hammer.fill")
                        StoreChannelPill("Sky Club", "moon.stars.fill")
                        StoreChannelPill("Everyday Lab", "flask.fill")
                    }

                    Text("All videos")
                        .font(.title2.bold())
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 250), spacing: 16)],
                        spacing: 20
                    ) {
                        ForEach(videos) { fixture in
                            StoreMediaTile(fixture: fixture, landscape: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                StoreTabBar(selected: "Explore")
            }
        }
        .accessibilityIdentifier("appStore.youtarr")
    }
}

struct AppStoreSettingsPreview: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Content") {
                    StoreSettingsRow("Visible Libraries", "square.grid.2x2.fill", "4 selected")
                    StoreSettingsRow("Home Screen", "house.fill", "Customized")
                    StoreSettingsRow("Library Views", "rectangle.stack.fill", nil)
                    StoreSettingsRow("Default Server", "server.rack", "Family Media")
                }

                Section("Youtarr") {
                    StoreSettingsRow("Connection", "sparkles", "Connected")
                    StoreSettingsRow("Show Explore Tab", "play.rectangle.on.rectangle.fill", "On")
                    StoreSettingsRow("My Requests", "clock.arrow.circlepath", nil)
                }

                Section("Downloads") {
                    StoreSettingsRow("Download Quality", "arrow.down.circle.fill", "1080p")
                }

                Section("Content Safety") {
                    StoreSettingsRow("Max Movie Rating", "film.fill", "PG")
                    StoreSettingsRow("Max TV Rating", "tv.fill", "TV-PG")
                    StoreSettingsRow("Exclude Unrated Content", "nosign", "On")
                }

                Section("Parental Access") {
                    StoreSettingsRow("Parent Lock", "lock.shield.fill", "PIN")
                    StoreSettingsRow("Maximum Playback Level", "speaker.wave.2.fill", "80%")
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("appStore.settings")
    }
}

private struct StoreScreenshotHeader: View {
    var body: some View {
        HStack {
            Image("BrandLockupWhite")
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 42)
            Spacer()
            Button {} label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.bold())
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
            }
            Button {} label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3.bold())
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
            }
        }
        .foregroundStyle(.white)
    }
}

private struct StoreMediaRail: View {
    let title: String
    let fixtures: [StoreMediaFixture]
    let landscape: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(fixtures) { fixture in
                        StoreMediaTile(fixture: fixture, landscape: landscape)
                            .frame(width: landscape ? 240 : 150)
                    }
                }
            }
        }
    }
}

private struct StoreMediaTile: View {
    let fixture: StoreMediaFixture
    let landscape: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LinearGradient(
                colors: fixture.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .aspectRatio(landscape ? 16 / 9 : 2 / 3, contentMode: .fit)
            .overlay {
                Image(systemName: fixture.symbol)
                    .font(.system(size: landscape ? 54 : 48, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(fixture.title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(fixture.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
    }
}

private struct StoreTabBar: View {
    let selected: String

    var body: some View {
        HStack(spacing: 36) {
            StoreTabItem("Home", "house.fill", selected: selected == "Home")
            StoreTabItem("Search", "magnifyingglass", selected: selected == "Search")
            StoreTabItem("Libraries", "rectangle.stack.fill", selected: selected == "Libraries")
            StoreTabItem("Explore", "sparkles", selected: selected == "Explore")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }
}

private struct StoreTabItem: View {
    let title: String
    let symbol: String
    let selected: Bool

    init(_ title: String, _ symbol: String, selected: Bool) {
        self.title = title
        self.symbol = symbol
        self.selected = selected
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title).font(.caption2)
        }
        .foregroundStyle(selected ? Color.green : Color.white.opacity(0.7))
    }
}

private struct StoreMetadataPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.12), in: Capsule())
    }
}

private struct StoreChannelPill: View {
    let title: String
    let symbol: String

    init(_ title: String, _ symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.1), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct StoreSettingsRow: View {
    let title: String
    let symbol: String
    let value: String?

    init(_ title: String, _ symbol: String, _ value: String?) {
        self.title = title
        self.symbol = symbol
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(title)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }
}

private struct StoreMediaFixture: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]

    init(_ title: String, _ subtitle: String, _ symbol: String, _ colors: [Color]) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.colors = colors
    }
}

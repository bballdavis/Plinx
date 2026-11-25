import SwiftUI
import PlinxUI
import PlinxCore

#if os(tvOS)

struct TvBrowseHeroMetrics {
    /// Aligns library rows with the shared leading hero content guide.
    static let alignedContentInset: CGFloat = 16
    /// Home rows include their row and focus-halo insets, so the hero copy
    /// uses the same visible leading guide rather than the library guide.
    static let homeAlignedContentInset: CGFloat = 42
    static let identityTrailingSafeInset: CGFloat = 64
    static let backdropHeightRatio: CGFloat = 0.68
    static let metadataRowHeight: CGFloat = 28
    static let summaryHeight: CGFloat = 112
    static let summaryLineLimit = 4

    static let horizontalFadeSoftStart: CGFloat = 0.14
    static let horizontalFadeMidpoint: CGFloat = 0.38
    static let horizontalFadeEnd: CGFloat = 0.58

    let heightRatio: CGFloat
    let leadingSafeAreaReduction: CGFloat
    let contentHorizontalPadding: CGFloat
    let contentTopPadding: CGFloat
    let metadataBottomPadding: CGFloat
    /// Home dissolves shelf content into the actual pinned backdrop at the
    /// viewport edge. Library keeps this at zero so filters are unaffected.
    let shelfTransitionHeight: CGFloat

    var backdropFadeStartLocation: CGFloat {
        min(heightRatio / Self.backdropHeightRatio, 1)
    }

    static let `default` = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0,
        contentHorizontalPadding: alignedContentInset,
        contentTopPadding: 1,
        metadataBottomPadding: 8,
        shelfTransitionHeight: 0
    )

    static let home = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0.5,
        contentHorizontalPadding: homeAlignedContentInset,
        contentTopPadding: 0,
        metadataBottomPadding: 8,
        shelfTransitionHeight: 20
    )
}

struct SharedTvBrowsePageLayout<NavigationContent: View, FilterContent: View, RowsContent: View>: View {
    let heroMedia: MediaItem?
    let showsFilters: Bool
    var heroMetrics: TvBrowseHeroMetrics = .default
    @ViewBuilder let navigationContent: () -> NavigationContent
    @ViewBuilder let filterContent: () -> FilterContent
    @ViewBuilder let rowsContent: (ScrollViewProxy) -> RowsContent

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { proxy in
                let heroHeight = proxy.size.height * heroMetrics.heightRatio
                let backdropHeight = proxy.size.height * TvBrowseHeroMetrics.backdropHeightRatio
                let rowsHeight = max(proxy.size.height - heroHeight, 0)
                let leadingShift = -(proxy.safeAreaInsets.leading * heroMetrics.leadingSafeAreaReduction)

                ZStack(alignment: .topLeading) {
                    Color.appBackground
                        .ignoresSafeArea()

                    if let heroMedia {
                        TvPinnedHeroBackdrop(
                            media: heroMedia,
                            identityGuideHeight: heroHeight,
                            bottomFadeStartLocation: heroMetrics.backdropFadeStartLocation
                        )
                        .frame(height: backdropHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }

                    VStack(spacing: 0) {
                        heroSection(
                            availableWidth: proxy.size.width,
                            topSafeAreaInset: proxy.safeAreaInsets.top
                        )
                            .frame(height: heroHeight)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if showsFilters {
                                    filterContent()
                                        .padding(.top, 6)
                                }

                                rowsContent(scrollProxy)
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 16)
                            .frame(minHeight: rowsHeight, alignment: .top)
                        }
                        .clipped()
                        .frame(height: rowsHeight)
                        .mask {
                            TvShelfViewportMask(topFadeHeight: heroMetrics.shelfTransitionHeight)
                        }
                    }

                }
                .padding(.leading, leadingShift)
                .frame(width: proxy.size.width - leadingShift, alignment: .leading)
            }
            .ignoresSafeArea(edges: [.top, .trailing])
        }
    }

    private func heroSection(availableWidth: CGFloat, topSafeAreaInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                navigationContent()

                Spacer(minLength: 0)

                if let heroMedia {
                    TvHeroMetadataPanel(media: heroMedia)
                        .frame(width: availableWidth * 0.54, alignment: .leading)
                        .padding(.bottom, heroMetrics.metadataBottomPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, heroMetrics.contentHorizontalPadding)
            .padding(.top, topSafeAreaInset + heroMetrics.contentTopPadding)
        }
        .clipped()
    }
}

/// Fades shelf content to transparency at the fixed top edge. The pinned hero
/// remains the only source of color, so bright and dark artwork blend naturally.
private struct TvShelfViewportMask: View {
    let topFadeHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if topFadeHeight > 0 {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topFadeHeight)
            }

            Rectangle().fill(.black)
        }
    }
}

struct TvPillButtonStyle: ButtonStyle {
    let isSelected: Bool
    let cornerRadius: CGFloat

    init(isSelected: Bool = false, cornerRadius: CGFloat = 16) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        TvPillButtonBody(configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius)
    }
}

private struct TvPillButtonBody: View {
    let configuration: TvPillButtonStyle.Configuration
    let isSelected: Bool
    let cornerRadius: CGFloat

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused ? 2.5 : 1.2)
            )
            .shadow(color: shadowColor, radius: isFocused ? 18 : 6)
            .scaleEffect(isFocused ? 1.08 : (isSelected ? 1.03 : 1.0))
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        return isFocused ? .white : .white.opacity(0.86)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isFocused ? 0.82 : 0.68)
        }
        return Color.white.opacity(isFocused ? 0.12 : 0.08)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isFocused ? 1.0 : 0.78)
        }
        return isFocused ? Color.accentColor.opacity(0.94) : Color.white.opacity(0.22)
    }

    private var shadowColor: Color {
        (isFocused || isSelected) ? Color.accentColor.opacity(isFocused ? 0.68 : 0.32) : .clear
    }
}

private struct TvHeroExternalRating: Identifiable, Hashable {
    let id: String
    let provider: String
    let value: String
    let isAudience: Bool

    /// The IMDb, Rotten Tomatoes and TMDB scores of a title, critics before
    /// audiences. Jellyfin's community score is left to the star fallback.
    static func resolve(from ratings: [MediaRating]) -> [TvHeroExternalRating] {
        var ratingsByID: [String: TvHeroExternalRating] = [:]

        for rating in ratings {
            let provider: String
            let isAudience: Bool
            let formattedValue: String
            switch rating.source {
            case .imdb:
                provider = "IMDb"
                isAudience = false
                formattedValue = String(format: "%.1f", rating.value)
            case .tmdb:
                provider = "TMDB"
                isAudience = false
                formattedValue = String(format: "%.1f", rating.value)
            case .rottenTomatoesCritic:
                provider = "Rotten Tomatoes"
                isAudience = false
                formattedValue = rottenTomatoesPercentage(rating.value)
            case .rottenTomatoesAudience:
                provider = "Rotten Tomatoes"
                isAudience = true
                formattedValue = rottenTomatoesPercentage(rating.value)
            case .jellyfinCritics:
                // Jellyfin's critic rating is already the Tomatometer percentage.
                provider = "Rotten Tomatoes"
                isAudience = false
                formattedValue = "\(Int(rating.value.rounded()))%"
            case .jellyfinCommunity:
                continue
            }

            let id = "\(normalizedProvider(provider))-\(isAudience ? "audience" : "critic")"
            guard ratingsByID[id] == nil else { continue }
            ratingsByID[id] = TvHeroExternalRating(
                id: id,
                provider: provider,
                value: formattedValue,
                isAudience: isAudience
            )
        }

        return ratingsByID.values.sorted { lhs, rhs in
            let lhsPriority = lhs.sortPriority
            let rhsPriority = rhs.sortPriority
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.isAudience != rhs.isAudience { return lhs.isAudience == false }
            return lhs.provider < rhs.provider
        }
    }

    /// Plex reports Rotten Tomatoes scores out of ten.
    private static func rottenTomatoesPercentage(_ rawValue: Double) -> String {
        let percentage = rawValue <= 10 ? rawValue * 10 : rawValue
        return "\(Int(percentage.rounded()))%"
    }

    static func normalizedProvider(_ provider: String) -> String {
        provider
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private var sortPriority: Int {
        switch Self.normalizedProvider(provider) {
        case "rottentomatoes", "rt": return isAudience ? 1 : 0
        case "imdb": return 2
        case "tmdb", "themoviedatabase", "themoviedb": return 3
        case "tvdb": return 4
        default: return 9
        }
    }
}

/// Full metadata of a hero title (its series, for an episode): the external
/// ratings and clear logo that listings leave out. The metadata panel and the
/// backdrop share one request per title. Requests go through the server's
/// `MediaServices`, so a title the safety boundary blocks resolves to `nil`.
@MainActor
enum TvHeroDetailsLoader {
    private static var cache: [MediaIdentity: MediaItem] = [:]
    private static var inFlight: [MediaIdentity: Task<MediaItem?, Never>] = [:]
    private static var cachedPolicyRevision: Int?
    private static let cacheLimit = 64

    static func details(for media: MediaItem, services: MediaServices) async -> MediaItem? {
        let revision = ContentSafetyGate.shared.revision
        if cachedPolicyRevision != revision {
            cache.removeAll()
            cachedPolicyRevision = revision
        }

        let identity = MediaIdentity(server: media.identity.server, itemID: media.metadataRatingKey)
        if let cached = cache[identity] {
            return cached
        }
        if let pending = inFlight[identity] {
            return await pending.value
        }

        let task = Task { @MainActor in
            try? await services.detail.mediaItem(id: identity.itemID)
        }
        inFlight[identity] = task
        let details = await task.value
        inFlight[identity] = nil

        guard let details, cachedPolicyRevision == ContentSafetyGate.shared.revision else { return details }
        if cache.count >= cacheLimit {
            cache.removeAll()
        }
        cache[identity] = details
        return details
    }
}

private struct TvHeroMetadataPanel: View {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?

    let media: MediaItem

    @State private var externalRatings: [TvHeroExternalRating] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataAndRatingsRow
                .frame(height: TvBrowseHeroMetrics.metadataRowHeight, alignment: .leading)
                .clipped()

            if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .lineSpacing(1.2)
                    .foregroundStyle(.brandSecondary)
                    .lineLimit(TvBrowseHeroMetrics.summaryLineLimit)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: TvBrowseHeroMetrics.summaryHeight,
                        maxHeight: TvBrowseHeroMetrics.summaryHeight,
                        alignment: .topLeading
                    )
            } else {
                Color.clear
                    .frame(height: TvBrowseHeroMetrics.summaryHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.72), radius: 3, y: 1)
        .task(id: media.identity) {
            await loadHeroMetadata()
        }
    }

    @ViewBuilder
    private var metadataAndRatingsRow: some View {
        if !metadataItems.isEmpty || !externalRatings.isEmpty || media.rating != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(metadataItems, id: \.self) { item in
                        Text(item)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.brandSecondary)
                    }

                    ForEach(externalRatings) { rating in
                        ratingBadge(rating)
                    }

                    if externalRatings.isEmpty, let score = media.rating {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                            Text(String(format: "%.1f", score))
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.brandSecondary)
                    }
                }
            }
        }
    }

    private func ratingBadge(_ rating: TvHeroExternalRating) -> some View {
        HStack(spacing: 5) {
            ratingProviderIconView(rating)
            Text(rating.value)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var metadataItems: [String] {
        var items: [String] = []
        if let tertiary = media.tertiaryLabel {
            items.append(tertiary)
        }
        if let year = media.year {
            items.append(String(year))
        }
        if let duration = media.duration {
            items.append(duration.mediaDurationText())
        }
        if let contentRating = media.contentRating {
            items.append(contentRating)
        }
        return items
    }

    private func loadHeroMetadata() async {
        externalRatings = []
        guard let services = registry.services(for: .playable(media), scoped: scopedServices) else { return }
        let details = await TvHeroDetailsLoader.details(for: media, services: services)
        guard !Task.isCancelled, let details else { return }
        externalRatings = TvHeroExternalRating.resolve(from: details.ratings)
    }

    @ViewBuilder
    private func ratingProviderIconView(_ rating: TvHeroExternalRating) -> some View {
        let assetName = ratingIconAssetName(rating)
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: ratingProviderSFSymbol(rating))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func ratingIconAssetName(_ rating: TvHeroExternalRating) -> String {
        let norm = TvHeroExternalRating.normalizedProvider(rating.provider)
        if (norm == "rottentomatoes" || norm == "rt") && rating.isAudience {
            return "rating.rt.audience"
        }
        switch norm {
        case "imdb": return "rating.imdb"
        case "rottentomatoes", "rt": return "rating.rt"
        case "tmdb", "themoviedatabase", "themoviedb": return "rating.tmdb"
        default: return "rating.\(norm)"
        }
    }

    private func ratingProviderSFSymbol(_ rating: TvHeroExternalRating) -> String {
        let norm = TvHeroExternalRating.normalizedProvider(rating.provider)
        if (norm == "rottentomatoes" || norm == "rt") && rating.isAudience {
            return "popcorn.fill"
        }
        switch norm {
        case "imdb": return "star.fill"
        case "rottentomatoes", "rt": return "circle.dotted.circle"
        case "tmdb", "themoviedatabase", "themoviedb": return "movieclapper.fill"
        case "tvdb": return "tv.fill"
        default: return "chart.bar.fill"
        }
    }
}

struct TvPinnedHeroBackdrop: View {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?

    let media: MediaItem
    let identityGuideHeight: CGFloat
    let bottomFadeStartLocation: CGFloat
    let showsIdentity: Bool
    let fillsBase: Bool

    @State private var backdrop: Image?
    @State private var displayedLogo: Image?
    @State private var displayedTitle: String = ""
    @State private var loadedIdentityForMedia: MediaIdentity?

    init(
        media: MediaItem,
        identityGuideHeight: CGFloat,
        bottomFadeStartLocation: CGFloat,
        showsIdentity: Bool = true,
        fillsBase: Bool = true
    ) {
        self.media = media
        self.identityGuideHeight = identityGuideHeight
        self.bottomFadeStartLocation = bottomFadeStartLocation
        self.showsIdentity = showsIdentity
        self.fillsBase = fillsBase
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if fillsBase {
                    Color.appBackground
                }

                // Until the artwork arrives (or when it fails) the base shows
                // through: the app background, or nothing when `fillsBase` is off.
                if let backdrop {
                    backdrop
                        .resizable()
                        .scaledToFill()
                        .frame(width: (proxy.size.width * 0.62) + 96, height: proxy.size.height)
                        .clipped()
                        .mask(
                            TvPinnedHeroImageMask(
                                bottomFadeStartLocation: bottomFadeStartLocation
                            )
                        )
                        .offset(x: 48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if showsIdentity {
                    heroIdentityOverlay
                        .frame(width: proxy.size.width * 0.34, alignment: .trailing)
                        .padding(.trailing, TvBrowseHeroMetrics.identityTrailingSafeInset)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: identityGuideHeight, alignment: .bottom)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .task(id: media.identity) {
                await loadImage()
                if showsIdentity {
                    await loadIdentityIfNeeded()
                }
            }
        }
    }

    /// The services of the title's server; the detail screen's own services when it is scoped to one.
    private var services: MediaServices? {
        registry.services(for: .playable(media), scoped: scopedServices)
    }

    @ViewBuilder
    private var heroIdentityOverlay: some View {
        Group {
            if let displayedLogo {
                displayedLogo
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 185, alignment: .trailing)
                    .clipped()
            } else {
                fallbackIdentityText
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .shadow(color: .black.opacity(0.58), radius: 16, y: 6)
    }

    private var fallbackIdentityText: some View {
        Text(displayedTitle.isEmpty ? media.primaryLabel : displayedTitle)
            .font(.system(size: 54, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func loadIdentityIfNeeded() async {
        guard loadedIdentityForMedia != media.identity else { return }

        var logo: Image?
        if let services {
            let details = await TvHeroDetailsLoader.details(for: media, services: services)
            if let logoPath = details?.preferredLogoPath ?? media.preferredLogoPath,
               let resource = try? await services.artwork.artwork(path: logoPath, width: 1800, height: 700)
            {
                logo = await ArtworkResourceView.image(for: resource)
            }
        }
        guard !Task.isCancelled else { return }

        // Keep the previous identity visible until the next one is fully resolved.
        displayedLogo = logo
        displayedTitle = media.primaryLabel
        loadedIdentityForMedia = media.identity
    }

    /// Keeps the previous backdrop until the next one is decoded, so moving
    /// along a row never flashes the base between titles.
    private func loadImage() async {
        let path = media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath

        guard let path, let services else {
            backdrop = nil
            return
        }

        var image: Image?
        if let resource = try? await services.artwork.artwork(path: path, width: 3840, height: 2160) {
            image = await ArtworkResourceView.image(for: resource)
        }
        guard !Task.isCancelled else { return }
        backdrop = image
    }
}

private struct TvPinnedHeroImageMask: View {
    let bottomFadeStartLocation: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.14), location: TvBrowseHeroMetrics.horizontalFadeSoftStart),
                .init(color: .black.opacity(0.70), location: TvBrowseHeroMetrics.horizontalFadeMidpoint),
                .init(color: .black, location: TvBrowseHeroMetrics.horizontalFadeEnd),
                .init(color: .black, location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: bottomFadeStartLocation),
                    .init(color: .black.opacity(0.86), location: 0.70),
                    .init(color: .black.opacity(0.38), location: 0.88),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

#endif

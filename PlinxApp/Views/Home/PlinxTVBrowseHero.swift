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

    var backdropFadeStartLocation: CGFloat {
        min(heightRatio / Self.backdropHeightRatio, 1)
    }

    static let `default` = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0,
        contentHorizontalPadding: alignedContentInset,
        contentTopPadding: 1,
        metadataBottomPadding: 8
    )

    static let home = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0.5,
        contentHorizontalPadding: homeAlignedContentInset,
        contentTopPadding: 0,
        metadataBottomPadding: 8
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
}

private struct TvHeroMetadataPanel: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

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
        .task(id: media.id) {
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

        do {
            let metadataRepository = try MetadataRepository(context: plexApiContext)
            let response = try await metadataRepository.getMetadata(ratingKey: media.metadataRatingKey)
            guard let item = response.mediaContainer.metadata?.first else { return }

            externalRatings = resolveExternalRatings(from: item)
        } catch {
            externalRatings = []
        }
    }

    private func resolveExternalRatings(from item: PlexItem) -> [TvHeroExternalRating] {
        var ratingsByID: [String: TvHeroExternalRating] = [:]

        func addRating(provider: String, value: Double, isAudience: Bool) {
            guard isSupportedProvider(provider) else { return }
            let providerID = normalizedProvider(provider)
            let id = "\(providerID)-\(isAudience ? "audience" : "critic")"
            guard ratingsByID[id] == nil else { return }
            ratingsByID[id] = TvHeroExternalRating(
                id: id,
                provider: provider,
                value: formattedRatingValue(value, provider: provider),
                isAudience: isAudience
            )
        }

        for rating in item.ratings ?? [] {
            let value = rating.value
            guard let provider = providerName(from: rating.image) ?? providerName(from: rating.type) else { continue }
            let isAudience = isAudienceRatingSource(rating.image) || isAudienceRatingSource(rating.type)
            addRating(provider: provider, value: value, isAudience: isAudience)
        }

        if let value = item.rating,
           let provider = providerName(from: item.ratingImage)
        {
            addRating(provider: provider, value: value, isAudience: false)
        }

        if let value = item.audienceRating,
           let provider = providerName(from: item.audienceRatingImage)
        {
            addRating(provider: provider, value: value, isAudience: true)
        }

        return ratingsByID.values.sorted { lhs, rhs in
            let lhsPriority = ratingSortPriority(lhs)
            let rhsPriority = ratingSortPriority(rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.isAudience != rhs.isAudience { return lhs.isAudience == false }
            return lhs.provider < rhs.provider
        }
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
        let norm = normalizedRatingProvider(rating.provider)
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
        let norm = normalizedRatingProvider(rating.provider)
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

    private func normalizedRatingProvider(_ provider: String) -> String {
        provider
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func providerName(from imageIdentifier: String?) -> String? {
        guard let imageIdentifier else { return nil }
        let value = imageIdentifier.lowercased()
        if value.contains("imdb") { return "IMDb" }
        if value.contains("rotten") || value.contains("tomato") || value == "rt" { return "Rotten Tomatoes" }
        if value.contains("tvdb") || value.contains("thetvdb") { return "TVDB" }
        if value.contains("tmdb") || value.contains("themoviedb") { return "TMDB" }
        return nil
    }

    private func isAudienceRatingSource(_ source: String?) -> Bool {
        guard let source else { return false }
        let value = source.lowercased()
        return value.contains("audience") || value.contains("user") || value.contains("popcorn")
    }

    private func normalizedProvider(_ provider: String) -> String {
        provider
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func isSupportedProvider(_ provider: String) -> Bool {
        switch normalizedProvider(provider) {
        case "imdb", "rottentomatoes", "rt", "tmdb", "themoviedatabase", "themoviedb", "tvdb":
            return true
        default:
            return false
        }
    }

    private func ratingSortPriority(_ rating: TvHeroExternalRating) -> Int {
        let provider = normalizedProvider(rating.provider)
        switch provider {
        case "rottentomatoes", "rt": return rating.isAudience ? 1 : 0
        case "imdb": return 2
        case "tmdb", "themoviedatabase", "themoviedb": return 3
        case "tvdb": return 4
        default: return 9
        }
    }

    private func formattedRatingValue(_ rawValue: Double, provider: String) -> String {
        let providerID = normalizedProvider(provider)
        if providerID == "rottentomatoes" || providerID == "rt" {
            let percentage = rawValue <= 10 ? rawValue * 10 : rawValue
            return "\(Int(percentage.rounded()))%"
        }

        if providerID == "imdb" {
            return String(format: "%.1f", rawValue)
        }

        return String(format: "%.1f", rawValue)
    }
}

private struct TvHeroIdentityView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem

    @State private var logoURL: URL?

    var body: some View {
        Group {
            if let logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                    } else {
                        fallbackTitle
                    }
                }
            } else {
                fallbackTitle
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: media.id) {
            await loadLogo()
        }
    }

    private var fallbackTitle: some View {
        Text(media.primaryLabel)
            .font(.system(size: 72, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.55)
    }

    private func loadLogo() async {
        logoURL = nil
        do {
            let metadataRepository = try MetadataRepository(context: plexApiContext)
            let response = try await metadataRepository.getMetadata(ratingKey: media.metadataRatingKey)
            guard let item = response.mediaContainer.metadata?.first else { return }
            guard let imageRepository = try? ImageRepository(context: plexApiContext) else { return }
            guard let logoPath = item.images?.first(where: { image in
                image.type.localizedCaseInsensitiveContains("logo")
            })?.url.path else { return }

            logoURL = imageRepository.transcodeImageURL(path: logoPath, width: 1800, height: 700)
        } catch {
            logoURL = nil
        }
    }
}

private struct TvPinnedHeroBackdrop: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem
    let identityGuideHeight: CGFloat
    let bottomFadeStartLocation: CGFloat

    @State private var imageURL: URL?
    @State private var displayedLogoURL: URL?
    @State private var displayedTitle: String = ""
    @State private var loadedIdentityForMediaID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.appBackground

                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            Color.appBackground
                        case .failure:
                            Color.appBackground
                        @unknown default:
                            Color.appBackground
                        }
                    }
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

                heroIdentityOverlay
                    .frame(width: proxy.size.width * 0.34, alignment: .trailing)
                    .padding(.trailing, TvBrowseHeroMetrics.identityTrailingSafeInset)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: identityGuideHeight, alignment: .bottom)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .task(id: media.id) {
                await loadImage()
                await loadIdentityIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var heroIdentityOverlay: some View {
        Group {
            if let displayedLogoURL {
                AsyncImage(url: displayedLogoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 185, alignment: .trailing)
                            .clipped()
                    } else {
                        fallbackIdentityText
                    }
                }
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
        guard loadedIdentityForMediaID != media.id else { return }

        do {
            let metadataRepository = try MetadataRepository(context: plexApiContext)
            let response = try await metadataRepository.getMetadata(ratingKey: media.metadataRatingKey)
            guard let item = response.mediaContainer.metadata?.first else { return }

            let imageRepository = try? ImageRepository(context: plexApiContext)
            let resolvedLogoURL: URL? = item.images?.first(where: { image in
                image.type.localizedCaseInsensitiveContains("logo")
            }).flatMap { image in
                imageRepository?.transcodeImageURL(path: image.url.path, width: 1800, height: 700)
            }

            await MainActor.run {
                // Keep the previous identity visible until the next one is fully resolved.
                if let resolvedLogoURL {
                    displayedLogoURL = resolvedLogoURL
                    displayedTitle = media.primaryLabel
                } else {
                    displayedLogoURL = nil
                    displayedTitle = media.primaryLabel
                }
                loadedIdentityForMediaID = media.id
            }
        } catch {
            await MainActor.run {
                displayedLogoURL = nil
                displayedTitle = media.primaryLabel
                loadedIdentityForMediaID = media.id
            }
        }
    }

    private func loadImage() async {
        let path = media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath

        guard let path else {
            imageURL = nil
            return
        }

        do {
            let imageRepository = try ImageRepository(context: plexApiContext)
            imageURL = imageRepository.transcodeImageURL(
                path: path,
                width: 3840,
                height: 2160,
                minSize: 1,
                upscale: 1
            )
        } catch {
            imageURL = nil
        }
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

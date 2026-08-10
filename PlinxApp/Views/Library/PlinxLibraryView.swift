import SwiftUI
import UIKit
import PlinxUI

struct PlinxLibraryView: View {
    @State var viewModel: SafeLibraryViewModel
    var topContent: AnyView? = nil
    var onSelectLibrary: (Library) -> Void
    var onRequestHomeNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0
    @State private var artworkRefreshToken = UUID()
    @AppStorage(LibraryCardLayoutPolicy.hotReloadLibraryArtworkStorageKey)
    private var hotReloadLibraryArtwork = false
    @AppStorage(LibraryCardLayoutPolicy.bannerArtworkCountStorageKey)
    private var storedBannerArtworkCount = 0

    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(SettingsManager.self) private var settingsManager
    #if os(tvOS)
    @EnvironmentObject private var tvFocusCoordinator: PlinxTVFocusCoordinator
    @FocusState private var focusedLibraryID: String?
    #endif

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.libraries.isEmpty {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.loading.plinx",
                        table: "Plinx"
                    ),
                    accessibilityIdentifier: "library.loading"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.libraries.isEmpty {
                PlinxErrorView(message: error) {
                    Task { await viewModel.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                libraryList
            }
        }
        .task { await viewModel.load() }
        .onAppear {
            if hotReloadLibraryArtwork {
                artworkRefreshToken = UUID()
            }
        }
        #if os(tvOS)
        .onChange(of: viewModel.libraries.map(\.id)) { oldIDs, ids in
            guard focusedLibraryID != nil else { return }
            focusedLibraryID = PlinxTVFocusCoordinator.resolvedContentID(
                currentID: focusedLibraryID,
                previousIDs: oldIDs,
                availableIDs: ids
            )
        }
        .onChange(of: contentFocusRequest) { _, _ in
            let ids = viewModel.libraries.map(\.id)
            focusedLibraryID = PlinxTVFocusCoordinator.resolvedContentID(
                currentID: focusedLibraryID,
                availableIDs: ids,
                preferredID: tvFocusCoordinator.rememberedContentTarget(
                    in: .library,
                    availableIDs: ids
                )
            )
        }
        .onChange(of: focusedLibraryID) { _, id in
            guard let id else { return }
            tvFocusCoordinator.rememberContentTarget(id, in: .library)
        }
        #endif
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
        .onChange(of: settingsManager.interface.hiddenLibraryIds) { _, hiddenIDs in
            viewModel.updateHiddenLibraryIDs(Set(hiddenIDs))
        }
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(spacing: libraryListSpacing) {
                if let topContent {
                    topContent
                }

                ForEach(viewModel.libraries) { library in
                    libraryTile(library, rowIndex: viewModel.libraries.firstIndex(where: { $0.id == library.id }) ?? 0)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, bottomContentPadding)
        }
    }

    @ViewBuilder
    private func libraryTile(_ library: Library, rowIndex: Int) -> some View {
        let tileBody = LibraryTileBody(
            library: library,
            bannerURLs: viewModel.bannerArtworkURLs(for: library),
            tileHeight: libraryTileHeight,
            artworkRefreshToken: artworkRefreshToken,
            hotReloadLibraryArtwork: hotReloadLibraryArtwork,
            bannerArtworkDisplayCount: bannerArtworkDisplayCount,
            ensureArtwork: { library, bannerCount in
                if hotReloadLibraryArtwork {
                    await viewModel.refreshArtwork(for: library, bannerCount: bannerCount)
                } else {
                    await viewModel.ensureArtwork(for: library, bannerCount: bannerCount)
                }
            },
            placeholder: { libraryPlaceholder(for: $0) },
            adaptiveArtwork: { artworkURLs, size in
                adaptiveLibraryArtwork(
                    artworkURLs: artworkURLs,
                    size: size,
                    placeholder: libraryPlaceholder(for: library)
                )
            }
        )

        #if os(tvOS)
        tileBody
            .focused($focusedLibraryID, equals: library.id)
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .plinxFocusSurface(
                isSelected: false,
                isFocused: focusedLibraryID == library.id
            )
            .onTapGesture { onSelectLibrary(library) }
            .onMoveCommand { direction in
                handleMoveCommand(direction, fromRow: rowIndex)
            }
        #else
        Button { onSelectLibrary(library) } label: {
            tileBody
        }
        .buttonStyle(.plain)
        #endif
    }

    #if os(tvOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection, fromRow rowIndex: Int) {
        switch direction {
        case .up:
            if rowIndex == 0 {
                onRequestHomeNavigationFocus()
            } else {
                focusedLibraryID = viewModel.libraries[rowIndex - 1].id
            }
        case .down:
            guard rowIndex + 1 < viewModel.libraries.count else { return }
            focusedLibraryID = viewModel.libraries[rowIndex + 1].id
        default:
            break
        }
    }
    #endif

    private func libraryPlaceholder(for library: Library) -> some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: library.iconName)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private var bannerArtworkDisplayCount: Int {
        LibraryCardLayoutPolicy.resolvedBannerArtworkDisplayCount(
            storedCount: storedBannerArtworkCount,
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom
        )
    }

    private var libraryTileHeight: CGFloat {
        #if os(tvOS)
        220
        #else
        160
        #endif
    }

    private var libraryListSpacing: CGFloat {
        #if os(tvOS)
        18
        #else
        10
        #endif
    }

    private var bottomContentPadding: CGFloat {
        #if os(tvOS)
        36
        #else
        120
        #endif
    }

    private func adaptiveLibraryArtwork(
        artworkURLs: [URL],
        size: CGSize,
        placeholder: some View,
    ) -> some View {
        let aspect = size.width / max(size.height, 1)
        let isUltraWide = aspect > 2.1
        let artwork = artworkURLs.prefix(bannerArtworkDisplayCount)

        guard let first = artwork.first else {
            return AnyView(placeholder)
        }

        return AnyView(ZStack {
            if isUltraWide {
                ultraWidePanelArtwork(
                    artworkURLs: Array(artwork),
                    size: size,
                    placeholder: placeholder
                )
            } else {
                AsyncImage(url: first) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                    } else {
                        placeholder
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height))
    }

    private func ultraWidePanelArtwork(
        artworkURLs: [URL],
        size: CGSize,
        placeholder: some View,
    ) -> some View {
        let sources: [URL] = Array(artworkURLs)
        guard !sources.isEmpty else { return AnyView(placeholder) }

        let displayCount = min(sources.count, bannerArtworkDisplayCount)
        let panelBaseWidth = size.width / CGFloat(max(displayCount, 1))
        let overlap: CGFloat = panelBaseWidth * 0.12
        let panelWidth = panelBaseWidth + overlap
        let panelAlignments: [Alignment] = (0..<displayCount).map { index in
            if index == 0 {
                return .leading
            } else if index == displayCount - 1 {
                return .trailing
            }
            return .center
        }
        let edgeBlurRadius: CGFloat = 5
        let displaySources = Array(sources.prefix(displayCount))

        return AnyView(ZStack {
            AsyncImage(url: displaySources.first) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .blur(radius: 18)
                        .overlay(Color.black.opacity(0.28))
                } else {
                    placeholder
                }
            }

            HStack(spacing: -overlap) {
                ForEach(displaySources.indices, id: \ .self) { index in
                    AsyncImage(url: displaySources[index]) { phase in
                        if case .success(let image) = phase {
                            ZStack {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: panelWidth, height: size.height, alignment: panelAlignments[index])
                                    .clipped()
                                    .blur(radius: edgeBlurRadius)
                                    .overlay(Color.black.opacity(0.16))
                                    .mask(edgeBlurMask(for: index, total: displaySources.count))

                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: panelWidth, height: size.height, alignment: panelAlignments[index])
                                    .clipped()
                            }
                            .frame(width: panelWidth, height: size.height)
                            .clipped()
                            .mask(panelEdgeMask(for: index, total: displaySources.count))
                        } else {
                            Color.clear.frame(width: panelWidth, height: size.height)
                        }
                    }
                }
            }
            .frame(width: size.width + overlap * CGFloat(max(displaySources.count - 1, 0)), height: size.height)
            .clipped()
        }
        .frame(width: size.width, height: size.height))
    }

    private func edgeBlurMask(for index: Int, total: Int) -> LinearGradient {
        var stops: [Gradient.Stop] = [.init(color: .clear, location: 0)]

        if index > 0 {
            stops += [
                .init(color: .clear, location: 0.15),
                .init(color: .white, location: 0.25),
                .init(color: .clear, location: 0.35),
            ]
        }

        if index < total - 1 {
            stops += [
                .init(color: .clear, location: 0.65),
                .init(color: .white, location: 0.75),
                .init(color: .clear, location: 0.85),
            ]
        }

        stops.append(.init(color: .clear, location: 1))
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private func panelEdgeMask(for index: Int, total: Int) -> LinearGradient {
        let leadingWhite: CGFloat = index == 0 ? 0.18 : 0.08
        let trailingWhite: CGFloat = index == total - 1 ? 0.82 : 0.92
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: leadingWhite),
                .init(color: .white, location: trailingWhite),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct LibraryTileBody<Placeholder: View, Artwork: View>: View {
    let library: Library
    let bannerURLs: [URL]
    let tileHeight: CGFloat
    let artworkRefreshToken: UUID
    let hotReloadLibraryArtwork: Bool
    let bannerArtworkDisplayCount: Int
    let ensureArtwork: (Library, Int) async -> Void
    let placeholder: (Library) -> Placeholder
    let adaptiveArtwork: ([URL], CGSize) -> Artwork

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                Group {
                    if !bannerURLs.isEmpty {
                        adaptiveArtwork(bannerURLs, proxy.size)
                    } else {
                        placeholder(library)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: tileHeight)
                .clipped()
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: library.iconName)
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(library.title)
                        .font(titleFont)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(labelPadding)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: tileHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isFocused ? Color.accentColor : .clear, lineWidth: isFocused ? 3 : 0)
        )
        .shadow(color: isFocused ? Color.accentColor.opacity(0.65) : .clear, radius: isFocused ? 30 : 0)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: artworkRefreshToken) {
            await ensureArtwork(library, bannerArtworkDisplayCount)
        }
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        36
        #else
        27
        #endif
    }

    private var titleFont: Font {
        #if os(tvOS)
        .title2.bold()
        #else
        .title3.bold()
        #endif
    }

    private var labelPadding: CGFloat {
        #if os(tvOS)
        20
        #else
        14
        #endif
    }

    private var cornerRadius: CGFloat {
        #if os(tvOS)
        22
        #else
        16
        #endif
    }
}

// MARK: - Springy Button

private struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

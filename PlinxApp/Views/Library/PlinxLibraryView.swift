import SwiftUI
import UIKit
import PlinxUI

struct PlinxLibraryView: View {
    @State var viewModel: SafeLibraryViewModel
    var topContent: AnyView? = nil
    var onSelectLibrary: (Library) -> Void
    @State private var artworkRefreshToken = UUID()
    @AppStorage(LibraryCardLayoutPolicy.hotReloadLibraryArtworkStorageKey)
    private var hotReloadLibraryArtwork = false
    @AppStorage(LibraryCardLayoutPolicy.bannerArtworkCountStorageKey)
    private var storedBannerArtworkCount = 0

    @Environment(\.safetyPolicy) private var safetyPolicy

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.libraries.isEmpty {
                PlinxBrandedLoadingView(titleKey: "library.loading.plinx")
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
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let topContent {
                    topContent
                }

                ForEach(viewModel.libraries) { library in
                    libraryTile(library)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            // Extra padding to prevent content from disappearing behind the
            // floating KidsMainTabPicker tab bar (~88pt).
            .padding(.bottom, 120)
        }
    }

    private func libraryTile(_ library: Library) -> some View {
        Button { onSelectLibrary(library) } label: {
            ZStack(alignment: .bottom) {
                GeometryReader { proxy in
                    Group {
                        let bannerURLs = viewModel.bannerArtworkURLs(for: library)
                        if !bannerURLs.isEmpty {
                            adaptiveLibraryArtwork(
                                artworkURLs: bannerURLs,
                                size: proxy.size,
                                placeholder: libraryPlaceholder(for: library)
                            )
                        } else {
                            libraryPlaceholder(for: library)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: library.iconName)
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(library.title)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .padding(14)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task(id: artworkRefreshToken) {
                if hotReloadLibraryArtwork {
                    await viewModel.refreshArtwork(for: library, bannerCount: bannerArtworkDisplayCount)
                } else {
                    await viewModel.ensureArtwork(for: library, bannerCount: bannerArtworkDisplayCount)
                }
            }
        }
        .buttonStyle(SpringyButtonStyle())
    }

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

// MARK: - Springy Button

private struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

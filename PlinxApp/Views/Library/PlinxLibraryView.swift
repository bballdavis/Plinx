import SwiftUI
import PlinxUI

struct PlinxLibraryView: View {
    @State var viewModel: SafeLibraryViewModel
    var topContent: AnyView? = nil
    var onSelectLibrary: (Library) -> Void

    @Environment(\.safetyPolicy) private var safetyPolicy

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.libraries.isEmpty {
                VStack(spacing: 16) {
                    PlinxieLoadingView()
                    Text("library.loading.plinx", tableName: "Plinx")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let topContent {
                    topContent
                }

                ForEach(viewModel.libraries) { library in
                    libraryTile(library)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 16)
            // Extra padding to prevent content from disappearing behind the
            // floating KidsMainTabPicker tab bar (~88pt).
            .padding(.bottom, 120)
        }
    }

    private func libraryTile(_ library: Library) -> some View {
        Button { onSelectLibrary(library) } label: {
            ZStack(alignment: .bottom) {
                GeometryReader { proxy in
                    // Background artwork
                    Group {
                        if let url = viewModel.artworkURL(for: library) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    adaptiveLibraryArtwork(
                                        image: img,
                                        library: library,
                                        size: proxy.size,
                                    )
                                } else {
                                    libraryPlaceholder(for: library)
                                }
                            }
                        } else {
                            libraryPlaceholder(for: library)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                }

                // Gradient + title
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: library.iconName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(library.title)
                            .font(.headline.bold())
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
            // contentShape ensures the entire visible frame is tappable on all
            // screen sizes, including iPad where transparent gradient tops would
            // otherwise fall outside the default hit region.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task { await viewModel.ensureArtwork(for: library) }
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

    private func adaptiveLibraryArtwork(image: Image, library: Library, size: CGSize) -> some View {
        let aspect = size.width / max(size.height, 1)
        let isUltraWide = aspect > 2.1

        return ZStack {
            if isUltraWide {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 18)
                    .overlay(Color.black.opacity(0.28))

                image
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: min(size.width * 0.72, library.type == .clip ? size.width * 0.82 : size.height * 1.55),
                        maxHeight: size.height,
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
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

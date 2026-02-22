import SwiftUI
import PlinxUI

struct PlinxLibraryView: View {
    @State var viewModel: SafeLibraryViewModel
    var onSelectLibrary: (Library) -> Void

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
    }

    private var libraryList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.libraries) { library in
                    libraryTile(library)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private func libraryTile(_ library: Library) -> some View {
        Button { onSelectLibrary(library) } label: {
            ZStack(alignment: .bottom) {
                // Background artwork
                Group {
                    if let url = viewModel.artworkURL(for: library) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
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
}

// MARK: - Springy Button

private struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

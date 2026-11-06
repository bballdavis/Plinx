import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx-branded server selection (replaces Strimr's SelectServerView)
//
// Functionally identical to Strimr's version but uses Plinx theme colors.
// ─────────────────────────────────────────────────────────────────────────────

struct SelectServerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        VStack(spacing: 24) {
            header
            content
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground.ignoresSafeArea())
        .tint(.accentColor)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                PlinxCompactDestructiveButton(
                    systemImage: "rectangle.portrait.and.arrow.right",
                    accessibilityLabel: Text("common.actions.logOut", tableName: "Plinx")
                ) {
                    isShowingLogoutConfirmation = true
                }
            }
            .padding(.horizontal, PlinxPageHeaderMetrics.horizontalPadding)
            .padding(.top, PlinxPageHeaderMetrics.topPadding)
            .padding(.bottom, PlinxPageHeaderMetrics.bottomPadding)
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("serverSelection.title")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("serverSelection.subtitle")
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.servers.isEmpty {
            PlinxBrandedLoadingView(
                context: .content,
                titleKey: "serverSelection.loading"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.servers.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("serverSelection.empty.title")
                .font(.headline)
                .foregroundStyle(.white)
            Text("serverSelection.empty.description")
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.load() }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    }
                    Text("serverSelection.retry")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlinxPrimaryActionButtonStyle())
            .disabled(viewModel.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        return Button {
            Task {
                await viewModel.select(server: server)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "server.rack")
                            .foregroundStyle(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    connectionSummary(for: server)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                if viewModel.selectingServerID == server.clientIdentifier {
                    ProgressView()
                        .tint(.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .opacity(
                viewModel.isSelecting && viewModel.selectingServerID != server.clientIdentifier
                    ? 0.6
                    : 1,
            )
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSelecting)
    }

    private func connectionSummary(for server: PlexCloudResource) -> some View {
        guard let connection = server.connections?.first else {
            return Text("serverSelection.connection.unavailable")
        }
        if connection.isLocal {
            return Text("serverSelection.connection.localFormat \(connection.address)")
        }
        if connection.isRelay {
            return Text("serverSelection.connection.relay")
        }
        return Text(connection.address)
    }
}

import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx-branded server selection (replaces Strimr's SelectServerView)
//
// Functionally identical to Strimr's version but uses Plinx theme colors.
// ─────────────────────────────────────────────────────────────────────────────

struct SelectServerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.plinxTheme) private var theme
    @State var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        VStack(spacing: 24) {
            header
            content
        }
        .padding(24)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("common.actions.logOut")
            }
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
            Text("serverSelection.subtitle")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.servers.isEmpty {
            ProgressView("serverSelection.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tint(theme.palette.primary)
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
            Text("serverSelection.empty.description")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.load() }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView().tint(theme.palette.primary)
                    }
                    Text("serverSelection.retry")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(theme.palette.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(viewModel.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        Button {
            Task { await viewModel.select(server: server) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(theme.palette.primary.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "server.rack")
                            .foregroundStyle(theme.palette.primary)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    connectionSummary(for: server)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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

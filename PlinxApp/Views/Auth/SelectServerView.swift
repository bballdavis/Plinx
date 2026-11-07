import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx-branded server selection (replaces Strimr's SelectServerView)
//
// Functionally identical to Strimr's version; presented as onboarding step 3 on
// the quiet-shell layout shared with sign-in and profile selection.
// ─────────────────────────────────────────────────────────────────────────────

struct SelectServerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isExpanded: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 32 : 24) {
            header
            content
        }
        .padding(.horizontal, isExpanded ? 48 : 24)
        .padding(.top, isExpanded ? 24 : 16)
        .padding(.bottom, 24)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PlinxAmbientBackground(intensity: .hero))
        .tint(.accentColor)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center) {
                PlinxCompactDestructiveButton(
                    systemImage: "rectangle.portrait.and.arrow.right",
                    accessibilityLabel: Text("common.actions.logOut", tableName: "Plinx")
                ) {
                    isShowingLogoutConfirmation = true
                }
                Spacer(minLength: 0)
                PlinxOnboardingStepIndicator(step: .server, isExpanded: isExpanded)
            }
            .padding(.horizontal, isExpanded ? 48 : PlinxPageHeaderMetrics.horizontalPadding)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("serverSelection.title")
                .font(.system(size: isExpanded ? 52 : 36, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Text("serverSelection.subtitle")
                .font(.system(isExpanded ? .title3 : .body, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.brandSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: "server.rack")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 4)
            Text("serverSelection.empty.title")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("serverSelection.empty.description")
                .foregroundStyle(Color.brandSecondary)
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
            .buttonStyle(PlinxActionButtonStyle())
            .padding(.top, 8)
            .disabled(viewModel.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        let isConnecting = viewModel.selectingServerID == server.clientIdentifier
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return Button {
            Task {
                await viewModel.select(server: server)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.white)
                    connectionSummary(for: server)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.brandSecondary)
                }

                Spacer(minLength: 8)

                if isConnecting {
                    ProgressView()
                        .tint(.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .opacity(viewModel.isSelecting && !isConnecting ? 0.6 : 1)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(PlinxBrand.surface))
            .overlay(
                shape.strokeBorder(
                    isConnecting ? Color.accentColor : Color.white.opacity(0.08),
                    lineWidth: isConnecting ? 2 : 1
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(PlinkButtonStyle())
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

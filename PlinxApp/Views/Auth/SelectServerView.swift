import PlinxUI
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Plinx server selection (iPhone, iPad and Apple TV)
//
// The one `SelectServerView`: the server step of Plex account setup, drawn on
// the quiet onboarding shell. Every server of the account is checked by
// default; a parent can uncheck servers and give an unreachable or relayed
// server a custom address. Driven by the absorbed `ServerSelectionViewModel`.
// ─────────────────────────────────────────────────────────────────────────────

struct SelectServerView: View {
    @State private var viewModel: ServerSelectionViewModel
    #if os(tvOS)
    @FocusState private var focusedServerID: String?
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(viewModel: ServerSelectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var isExpanded: Bool {
        #if os(tvOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        content
            .background(PlinxAmbientBackground(intensity: .hero))
            .tint(.accentColor)
            .task { await viewModel.load() }
            .taskPresentation(item: $viewModel.customAddressModel) { model in
                CustomServerAddressView(model: model)
            }
            .accessibilityIdentifier("serverSelection")
    }

    // MARK: - Layout

    #if os(tvOS)
    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                header
                Spacer(minLength: 24)
                PlinxOnboardingStepIndicator(step: .server, isExpanded: true)
            }
            serverContent
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: viewModel.servers) { _, servers in
            if focusedServerID == nil, let first = servers.first {
                focusedServerID = first.clientIdentifier
            }
        }
    }
    #else
    private var content: some View {
        GeometryReader { proxy in
            let layout = PlinxOnboardingLayout(width: proxy.size.width, height: proxy.size.height)
            let arrangement = layout.usesColumns
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: isExpanded ? 32 : 24))
            arrangement {
                header
                    .frame(maxWidth: layout.usesColumns ? 280 : .infinity, alignment: .leading)
                serverContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, isExpanded ? 24 : 16)
            .padding(.bottom, 24)
            .frame(maxWidth: layout.usesColumns ? 1180 : 760)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center) {
                PlinxOnboardingBackButton()
                Spacer(minLength: 0)
                PlinxOnboardingStepIndicator(step: .server, isExpanded: isExpanded)
            }
            .padding(.horizontal, isExpanded ? 48 : PlinxPageHeaderMetrics.horizontalPadding)
            .padding(.top, PlinxPageHeaderMetrics.topPadding)
            .padding(.bottom, PlinxPageHeaderMetrics.bottomPadding)
        }
    }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("serverSelection.title")
                .font(.system(size: isExpanded ? 52 : 36, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Text("serverSelection.multiple.subtitle")
                .font(.system(isExpanded ? .title3 : .body, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.brandSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var serverContent: some View {
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
                LazyVStack(spacing: isTV ? 28 : 12) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }

                    continueButton
                        .padding(.top, isTV ? 24 : 12)
                }
                .padding(.vertical, isTV ? 24 : 8)
                #if os(tvOS)
                .padding(.horizontal, 24)
                #endif
            }
            #if os(tvOS)
            .scrollClipDisabled()
            #endif
        }
    }

    private var isTV: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: isTV ? 64 : 40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 4)
            Text("serverSelection.empty.title")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("serverSelection.empty.description")
                .foregroundStyle(Color.brandSecondary)
                .multilineTextAlignment(.center)
            PlinxOnboardingActionButton {
                Task { await viewModel.load() }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    }
                    Text("serverSelection.retry")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: isTV ? 480 : .infinity)
            .padding(.top, 8)
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("serverSelection.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var continueButton: some View {
        PlinxOnboardingActionButton {
            viewModel.continueWithSelection()
        } label: {
            Text("common.actions.continue")
        }
        .frame(maxWidth: isTV ? 480 : 460)
        .disabled(viewModel.selectedServerIDs.isEmpty)
        .frame(maxWidth: .infinity)
        #if os(tvOS)
        .focusSection()
        #endif
        .accessibilityIdentifier("serverSelection.continue")
    }

    // MARK: - Rows

    private func serverRow(_ server: PlexCloudResource) -> some View {
        VStack(alignment: .trailing, spacing: isTV ? 20 : 6) {
            serverToggle(server)
            if viewModel.suggestsCustomAddress(for: server) {
                Button {
                    viewModel.showCustomAddress(for: server)
                } label: {
                    Text("serverSelection.customAddress.suggest")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                #if os(tvOS)
                .plinxTVFocusButton(style: PlinxFocusSurfaceStyle(cornerRadius: 16, focusedFillOpacity: 0.1))
                #else
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 44)
                #endif
                .accessibilityIdentifier("serverSelection.customAddress.\(server.clientIdentifier)")
            }
        }
    }

    private func serverToggle(_ server: PlexCloudResource) -> some View {
        let isSelected = viewModel.isSelected(server)
        let shape = RoundedRectangle(cornerRadius: isTV ? 24 : 20, style: .continuous)

        return Button {
            viewModel.toggle(server)
        } label: {
            HStack(spacing: isTV ? 28 : 14) {
                Image(systemName: "server.rack")
                    .font(.system(size: isTV ? 30 : 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: isTV ? 72 : 48, height: isTV ? 72 : 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.system(isTV ? .title3 : .headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.white)
                    ServerConnectionSummary(state: viewModel.probeState(of: server))
                        .font(.system(isTV ? .callout : .subheadline, design: .rounded, weight: .medium))
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: isTV ? 34 : 24, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.4))
            }
            .padding(isTV ? 28 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(PlinxBrand.surface))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .contentShape(shape)
        }
        #if os(tvOS)
        .focused($focusedServerID, equals: server.clientIdentifier)
        .plinxTVFocusButton(
            isSelected: isSelected,
            style: PlinxFocusSurfaceStyle(cornerRadius: 24, focusedFillOpacity: 0.08)
        )
        #else
        .buttonStyle(PlinkButtonStyle())
        #endif
        .contextMenu {
            Button("serverSelection.customAddress.use") {
                viewModel.showCustomAddress(for: server)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("serverSelection.server.\(server.clientIdentifier)")
    }
}

import SwiftUI

struct DefaultServerSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State var viewModel: ServerSelectionViewModel

    var body: some View {
        List {
            if viewModel.isLoading, viewModel.servers.isEmpty {
                ProgressView(
                    String(localized: "settings.server.loading", table: "Plinx")
                )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if viewModel.servers.isEmpty {
                ContentUnavailableView(
                    String(localized: "settings.server.empty.title", table: "Plinx"),
                    systemImage: "server.rack",
                    description: Text("settings.server.empty.description", tableName: "Plinx")
                )
                .listRowBackground(Color.clear)
            } else {
                Section(
                    String(localized: "settings.server.choose", table: "Plinx")
                ) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverOptionRow(server)
                    }
                }
            }
        }
        .navigationTitle(Text("settings.server.default.title", tableName: "Plinx"))
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.appBackground.ignoresSafeArea())
        .tint(.accentColor)
        .task {
            await viewModel.load()
        }
    }

    private func serverOptionRow(_ server: PlexCloudResource) -> some View {
        let isSelected = viewModel.selectingServerID == server.clientIdentifier
        let isCurrent = sessionManager.plexServer?.clientIdentifier == server.clientIdentifier

        return Button {
            Task {
                await viewModel.select(server: server)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .foregroundStyle(.primary)

                    if isCurrent {
                        Text("settings.server.currentlyActive", tableName: "Plinx")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    ProgressView()
                        .tint(.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .opacity(viewModel.isSelecting && !isSelected ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSelecting)
    }
}

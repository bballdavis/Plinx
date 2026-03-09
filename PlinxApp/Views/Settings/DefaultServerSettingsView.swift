import SwiftUI

struct DefaultServerSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State var viewModel: ServerSelectionViewModel

    var body: some View {
        List {
            if viewModel.isLoading, viewModel.servers.isEmpty {
                ProgressView("Loading Servers...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if viewModel.servers.isEmpty {
                ContentUnavailableView(
                    "No Servers Available",
                    systemImage: "server.rack",
                    description: Text("Make sure your Plex servers are online, then try again.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Choose Default Server") {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverOptionRow(server)
                    }
                }
            }
        }
        .navigationTitle("Default Server")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
                        Text("Currently Active")
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

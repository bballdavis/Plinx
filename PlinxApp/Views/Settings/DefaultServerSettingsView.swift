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

                Section {
                    Button {
                        viewModel.setAsDefault = true
                        Task { await viewModel.saveSelection() }
                    } label: {
                        HStack {
                            if viewModel.isSelecting {
                                ProgressView().tint(.white)
                            }
                            Text("Save Default Server")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(Color.accentColor)
                    .foregroundStyle(.white)
                    .disabled(!viewModel.canSaveSelection)
                } footer: {
                    Text("Changing the default server also switches your active server and refreshes library data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Default Server")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .tint(.accentColor)
        .task {
            await viewModel.load()
        }
    }

    private func serverOptionRow(_ server: PlexCloudResource) -> some View {
        let isSelected = viewModel.selectedServerID == server.clientIdentifier
        let isCurrent = sessionManager.plexServer?.clientIdentifier == server.clientIdentifier

        return Button {
            viewModel.chooseServer(server)
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

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
    }
}

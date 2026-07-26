import SwiftUI

/// Parent-only configuration for Youtarr. This view is reachable only from
/// `PlinxSettingsView`, whose contents are protected by the parental gate.
struct YoutarrSettingsView: View {
    private let configurationStore: YoutarrConfigurationStore
    private let clientFactory: (YoutarrConfiguration) -> YoutarrClient

    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var capabilities: YoutarrCapabilities?
    @State private var connectionTask: Task<Void, Never>?

    init(
        configurationStore: YoutarrConfigurationStore = YoutarrConfigurationStore(),
        clientFactory: @escaping (YoutarrConfiguration) -> YoutarrClient = { YoutarrClient(configuration: $0) }
    ) {
        self.configurationStore = configurationStore
        self.clientFactory = clientFactory
    }

    var body: some View {
        Form {
            Section {
                TextField(text: $baseURL) {
                    Text("youtarr.settings.baseURL", tableName: "Plinx")
                }
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                #endif

                SecureField(text: $apiKey) {
                    Text("youtarr.settings.apiKey", tableName: "Plinx")
                }
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif

                Text("youtarr.settings.apiKey.help", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("youtarr.settings.connection", tableName: "Plinx")
            } footer: {
                Text("youtarr.settings.address.help", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(action: save) {
                    Text("youtarr.settings.save", tableName: "Plinx")
                }
                .disabled(isWorking)

                Button(action: testConnection) {
                    Text("youtarr.settings.test", tableName: "Plinx")
                }
                .disabled(isWorking)

                if isWorking {
                    HStack {
                        ProgressView()
                        Text("youtarr.settings.testing", tableName: "Plinx")
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            if let capabilities {
                Section {
                    if let serverVersion = capabilities.serverVersion, !serverVersion.isEmpty {
                        summaryRow("youtarr.settings.serverVersion", value: serverVersion)
                    }
                    summaryRow("youtarr.settings.apiVersion", value: capabilities.apiVersion)
                    summaryRow("youtarr.settings.role", value: roleDescription(capabilities.role))
                    summaryRow("youtarr.settings.scopes", value: String(capabilities.scopes.count))
                    summaryRow(
                        "youtarr.settings.catalog",
                        value: YoutarrStrings.value(capabilities.features.catalog ? "youtarr.availability.available" : "youtarr.availability.unavailable")
                    )
                } header: {
                    Text("youtarr.settings.summary", tableName: "Plinx")
                }
            }

            Section {
                Button(role: .destructive, action: removeConfiguration) {
                    Text("youtarr.settings.remove", tableName: "Plinx")
                }
                    .disabled(isWorking || baseURL.isEmpty)
            } footer: {
                Text("youtarr.settings.remove.help", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("youtarr.settings.title", tableName: "Plinx"))
        .task {
            baseURL = configurationStore.storedBaseURL ?? ""
        }
        .onDisappear {
            cancelConnectionTest()
        }
    }

    private func save() {
        do {
            _ = try configurationStore.save(baseURL: baseURL, apiKey: apiKey)
            baseURL = configurationStore.storedBaseURL ?? baseURL
            apiKey = "" // Never redisplay or retain a saved credential in view state.
            capabilities = nil
            statusMessage = YoutarrStrings.value("youtarr.status.saved")
        } catch let error as LocalizedError {
            statusMessage = error.errorDescription ?? YoutarrStrings.value("youtarr.error.save")
        } catch {
            statusMessage = YoutarrStrings.value("youtarr.error.save")
        }
    }

    private func testConnection() {
        connectionTask?.cancel()
        isWorking = true
        statusMessage = nil
        capabilities = nil
        connectionTask = Task { @MainActor in
            defer {
                isWorking = false
                connectionTask = nil
            }
            do {
                let configuration = try configurationStore.draft(baseURL: baseURL, apiKey: apiKey)
                let testedCapabilities = try await clientFactory(configuration).capabilities()
                try Task.checkCancellation()
                capabilities = testedCapabilities
                statusMessage = YoutarrStrings.value("youtarr.status.verified")
            } catch is CancellationError {
                // View dismissal and replacement tests are intentionally silent.
            } catch let error as LocalizedError {
                statusMessage = error.errorDescription ?? YoutarrStrings.value("youtarr.error.test")
            } catch {
                statusMessage = YoutarrStrings.value("youtarr.error.test")
            }
        }
    }

    private func cancelConnectionTest() {
        connectionTask?.cancel()
        connectionTask = nil
        isWorking = false
    }

    private func removeConfiguration() {
        do {
            try configurationStore.clear()
            baseURL = ""
            apiKey = ""
            capabilities = nil
            statusMessage = YoutarrStrings.value("youtarr.status.removed")
        } catch {
            statusMessage = YoutarrStrings.value("youtarr.error.remove")
        }
    }

    private func roleDescription(_ role: YoutarrRole) -> String {
        switch role {
        case .view: return YoutarrStrings.value("youtarr.role.view")
        case .request: return YoutarrStrings.value("youtarr.role.request")
        case .delete: return YoutarrStrings.value("youtarr.role.delete")
        case .admin: return YoutarrStrings.value("youtarr.role.admin")
        case .unknown: return YoutarrStrings.value("youtarr.role.unknown")
        }
    }

    @ViewBuilder
    private func summaryRow(_ title: String, value: String) -> some View {
        LabeledContent(content: {
            Text(value)
        }, label: {
            Text(LocalizedStringKey(title), tableName: "Plinx")
        })
    }
}

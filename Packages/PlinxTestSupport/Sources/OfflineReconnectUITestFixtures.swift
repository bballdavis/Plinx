import Foundation

public enum OfflineReconnectUITestFixtures {
    public static let screenName = "offlineReconnect"
    public static let onlineStateAccessibilityID = "offlineReconnect.state.online"

    public static func isActive(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains("--ui-testing") && environment["PLINX_UI_TEST_SCREEN"] == screenName
    }

    public static func seedIfNeeded(environment: [String: String]) {
        guard environment["PLINX_UI_TEST_SCREEN"] == screenName else { return }

        let downloadsDirectory = DownloadUITestFixtures.buildDownloadsDirectory()

        do {
            if FileManager.default.fileExists(atPath: downloadsDirectory.path) {
                try FileManager.default.removeItem(at: downloadsDirectory)
            }
            try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

            let items = DownloadUITestFixtures.makeItems(seed: 23).map { item in
                DownloadUITestItem(
                    id: item.id,
                    status: .completed,
                    progress: 1,
                    bytesWritten: item.totalBytes,
                    totalBytes: item.totalBytes,
                    taskIdentifier: nil,
                    errorMessage: nil,
                    metadata: item.metadata
                )
            }

            for item in items {
                let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try DownloadUITestFixtures.writePosterImage(for: item, to: folderURL)
            }

            let indexURL = downloadsDirectory.appendingPathComponent("index.json", isDirectory: false)
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            assertionFailure("Failed to seed offline reconnect UI-test fixtures: \(error)")
        }
    }
}

import SwiftUI

/// Library name with its server underneath when the profile has several servers.
struct LibrarySettingsLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.cardMetadata)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

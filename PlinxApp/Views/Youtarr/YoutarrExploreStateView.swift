import SwiftUI
import PlinxCore
import PlinxUI

struct YoutarrExploreStateView: View {
    let systemImage: String
    let titleKey: String
    var titleAccessibilityIdentifier: String? = nil
    var messageKey: String?
    var message: String?
    var showsProgress = false
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(LocalizedStringKey(titleKey), tableName: "Plinx")
            } icon: {
                Image(systemName: systemImage)
            }
            .accessibilityIdentifier(titleAccessibilityIdentifier ?? titleKey)
        } description: {
            if let messageKey {
                Text(LocalizedStringKey(messageKey), tableName: "Plinx")
            } else if let message {
                Text(message)
            }
        } actions: {
            if showsProgress {
                PlinxLoadingStateView(
                    role: .content,
                    accessibilityIdentifier: "youtarr.loading"
                )
                    .accessibilityLabel(Text(LocalizedStringKey(titleKey), tableName: "Plinx"))
            }
            if let retry {
                PlinxChromeActionButton(
                    titleKey: "youtarr.explore.retry",
                    systemImage: "arrow.clockwise",
                    action: retry
                )
                .accessibilityIdentifier("youtarr.explore.retry")
            }
        }
    }
}

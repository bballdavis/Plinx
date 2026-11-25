import PlinxUI
import SwiftUI

/// Recovery card shown only when the family's media truly cannot be reached:
///
/// - `.sessionUpdate`: the saved session could not be restored
///   (`SessionManager.Status.migrationFailed`: the one-time update to accounts
///   and profiles needs the Keychain and plex.tv). The previous session is
///   kept; retrying hydrates again, and the app also retries when the network
///   returns. On iPhone and iPad, offline Downloads may sit underneath.
/// - `.serversUnreachable`: a ready session on Apple TV (no downloads) whose
///   every server is unreachable; retrying reconnects the servers.
///
/// Never shown while the session is still connecting.
struct PlinxConnectionRecoveryView: View {
    enum Context {
        case sessionUpdate
        case serversUnreachable
    }

    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @State private var isRetrying = false

    var context: Context = .sessionUpdate

    private var isOffline: Bool {
        !registry.availability.hasNetworkPath
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isOffline ? "wifi.exclamationmark" : "arrow.triangle.2.circlepath")
                .font(.title2)
                .accessibilityHidden(true)
            Text("offline.recovery.title", tableName: "Plinx")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            message
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                retry()
            } label: {
                if isRetrying {
                    ProgressView()
                        .accessibilityLabel(Text("offline.recovery.retry", tableName: "Plinx"))
                } else {
                    Text("offline.recovery.retry", tableName: "Plinx")
                }
            }
            #if os(tvOS)
            .plinxTVFocusButton(style: PlinxFocusSurfaceStyle(cornerRadius: 18, focusedFillOpacity: 0.12))
            #else
            .buttonStyle(.borderedProminent)
            #endif
            .disabled(isRetrying)
            .accessibilityIdentifier("connectionRecovery.retry")
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connectionRecovery")
    }

    /// True when offline Downloads are shown underneath the card.
    var downloadsAvailable = false

    @ViewBuilder
    private var message: some View {
        if isOffline {
            if downloadsAvailable {
                Text("offline.recovery.message", tableName: "Plinx")
            } else {
                Text("offline.recovery.tvMessage", tableName: "Plinx")
            }
        } else {
            switch context {
            case .sessionUpdate:
                Text(Self.updateMessage)
            case .serversUnreachable:
                Text(Self.serversUnreachableMessage)
            }
        }
    }

    private func retry() {
        guard !isRetrying else { return }
        isRetrying = true
        Task {
            switch context {
            case .sessionUpdate:
                await sessionManager.hydrate()
            case .serversUnreachable:
                registry.retryUnavailable()
                await registry.waitForFirstReady(timeout: .seconds(5))
            }
            isRetrying = false
        }
    }

    static var updateMessage: String {
        String(
            localized: "offline.recovery.plinx.updateMessage",
            defaultValue: "Plinx couldn’t finish updating your sign-in. Your account is kept. Try again in a moment.",
            table: "Plinx"
        )
    }

    static var serversUnreachableMessage: String {
        String(
            localized: "offline.recovery.plinx.serversUnreachable",
            defaultValue: "Plinx can’t reach your media server. Make sure it’s turned on, then try again.",
            table: "Plinx"
        )
    }
}

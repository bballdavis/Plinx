import SwiftUI

/// Recovery affordance for a previously enrolled account after a remote
/// session failure. On iPhone and iPad, local Downloads remain underneath.
struct PlinxConnectionRecoveryView: View {
    @Environment(PlinxSessionAccessCoordinator.self) private var access
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        if case let .offline(snapshot) = access.state {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark").font(.title2)
                Text("offline.recovery.title", tableName: "Plinx").font(.headline)
                #if os(tvOS)
                Text("offline.recovery.tvMessage", tableName: "Plinx")
                    .font(.subheadline).multilineTextAlignment(.center)
                #else
                Text("offline.recovery.message", tableName: "Plinx")
                    .font(.subheadline).multilineTextAlignment(.center)
                #endif
                Text(snapshot.serverName).font(.caption).foregroundStyle(.secondary)
                Button {
                    access.reconnect(using: sessionManager)
                } label: {
                    if access.isReconnecting {
                        ProgressView()
                            .accessibilityLabel(Text("offline.recovery.retry", tableName: "Plinx"))
                    } else {
                        Text("offline.recovery.retry", tableName: "Plinx")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(access.isReconnecting)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
    }
}

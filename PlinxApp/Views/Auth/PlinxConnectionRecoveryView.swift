import SwiftUI

/// Recovery affordance shown over the stable local root after a remote
/// session failure. The local Downloads surface remains available underneath.
struct PlinxConnectionRecoveryView: View {
    @Environment(PlinxSessionAccessCoordinator.self) private var access
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        if case let .offline(snapshot) = access.state {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark").font(.title2)
                Text("offline.recovery.title", tableName: "Plinx").font(.headline)
                Text("offline.recovery.message", tableName: "Plinx")
                    .font(.subheadline).multilineTextAlignment(.center)
                Text(snapshot.serverName).font(.caption).foregroundStyle(.secondary)
                Button {
                    access.reconnect { await sessionManager.hydrate(); return sessionManager.status == .ready }
                } label: {
                    Text("offline.recovery.retry", tableName: "Plinx")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
    }
}

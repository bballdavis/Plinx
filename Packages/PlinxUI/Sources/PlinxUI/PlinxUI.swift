import SwiftUI
import PlinxCore

public struct PlinxPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Plinx")
                .font(.largeTitle.bold())
            Text("Core v\(PlinxCore.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

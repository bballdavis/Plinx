    import SwiftUI

public struct PlinxieLoadingView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(.orange)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("Plinx")
                .font(.headline)
        }
        .padding()
    }
}

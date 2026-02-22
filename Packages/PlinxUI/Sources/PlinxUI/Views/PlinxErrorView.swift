import SwiftUI

/// A kid-friendly inline error state with retry support.
public struct PlinxErrorView: View {
    public let message: String
    public let onRetry: (() -> Void)?

    @Environment(\.plinxTheme) private var theme

    public init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(theme.palette.accent)
                .symbolEffect(.bounce, options: .repeating)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)

            if let onRetry {
                LiquidGlassButton("Try Again", action: onRetry)
            }
        }
        .padding()
    }
}

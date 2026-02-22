import SwiftUI

/// Applies bouncing symbol effect where available, otherwise no-op.
private struct BounceEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.symbolEffect(.bounce, options: .repeating)
        } else {
            content
        }
    }
}

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
                .modifier(BounceEffectModifier())

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

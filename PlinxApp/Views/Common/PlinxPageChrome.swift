import SwiftUI
import PlinxUI

// Onboarding controls ported from the visual refresh. The broader page-chrome
// integration remains separate from the App Review demo change.

enum PlinxPageHeaderMetrics {
    #if os(tvOS)
    static let horizontalPadding: CGFloat = 42
    static let topPadding: CGFloat = 26
    static let bottomPadding: CGFloat = 20
    #else
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 10
    #endif
}

/// The app's action-button language, shared with media detail's Play and
/// secondary actions and the long-press "More Info" options: accent-tinted
/// liquid glass, an accent outline with a soft accent glow, and a spring press
/// that tightens the glow. Use `.primary` for the one main action on a screen
/// and `.secondary` for supporting actions.
struct PlinxActionButtonStyle: ButtonStyle {
    enum Treatment {
        case primary
        case secondary
    }

    var treatment: Treatment = .primary
    var minHeight: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        PlinxActionButtonBody(configuration: configuration, treatment: treatment, minHeight: minHeight)
    }
}

private struct PlinxActionButtonBody: View {
    let configuration: PlinxActionButtonStyle.Configuration
    let treatment: PlinxActionButtonStyle.Treatment
    let minHeight: CGFloat?
    @Environment(\.isEnabled) private var isEnabled

    private var isPrimary: Bool { treatment == .primary }
    private var cornerRadius: CGFloat { isPrimary ? 20 : 16 }
    private var resolvedMinHeight: CGFloat { minHeight ?? (isPrimary ? 64 : 52) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .font(isPrimary ? .title3.weight(.bold) : .headline)
            .foregroundStyle(isPrimary ? Color.white : Color.accentColor)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: resolvedMinHeight)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(Color.accentColor.opacity(isPrimary ? 0.30 : 0.18))
                    }
            }
            .overlay {
                shape.stroke(
                    Color.accentColor.opacity(configuration.isPressed ? 0.95 : 0.68),
                    lineWidth: configuration.isPressed ? 2 : 1.5
                )
            }
            .overlay {
                // Inner highlight keeps the glass edge crisp on bright accents.
                shape
                    .inset(by: 1.5)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(
                color: Color.accentColor.opacity(configuration.isPressed ? 0.10 : (isPrimary ? 0.26 : 0.18)),
                radius: configuration.isPressed ? 3 : (isPrimary ? 14 : 8),
                y: configuration.isPressed ? 2 : 5
            )
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PlinxCompactDestructiveButton: View {
    let systemImage: String
    let accessibilityLabel: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

import SwiftUI

/// A fullscreen overlay that absorbs all touches when `isEnabled` is `true`.
///
/// The lock is dismissed by a **triple-tap** gesture anywhere on screen.
/// Usage:
/// ```swift
/// MyContentView()
///     .modifier(BabyLockModifier(isEnabled: $babyLockEnabled))
/// ```
public struct BabyLockModifier: ViewModifier {
    @Binding public var isEnabled: Bool

    public init(isEnabled: Binding<Bool>) {
        self._isEnabled = isEnabled
    }

    public func body(content: Content) -> some View {
        ZStack {
            content
            if isEnabled {
                // Nearly-transparent layer that captures all touches.
                // opacity(0.001) is non-zero so hit-testing registers hits.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isEnabled = false
                        }
                    }
                    // Single/double taps are swallowed (no action) so children can't receive them.
                    .onTapGesture(count: 1) {}
                    .overlay(alignment: .top) {
                        BabyLockBadge()
                            .padding(.top, 60)
                            .allowsHitTesting(false)
                    }
            }
        }
    }
}

/// Non-interactive badge shown while baby lock is active.
private struct BabyLockBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("Triple-tap to unlock")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
        )
        .opacity(0.85)
    }
}

public extension View {
    func babyLock(isEnabled: Binding<Bool>) -> some View {
        modifier(BabyLockModifier(isEnabled: isEnabled))
    }
}

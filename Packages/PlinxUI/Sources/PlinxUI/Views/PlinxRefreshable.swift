import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Applies Plinx's branded pull-to-refresh presentation while preserving
/// SwiftUI's native refresh gesture and async action semantics.
public extension View {
    func plinxRefreshable(
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        modifier(PlinxRefreshableModifier(action: action))
    }
}

private struct PlinxRefreshableModifier: ViewModifier {
    let action: @Sendable () async -> Void

    @State private var isRefreshing = false

    func body(content: Content) -> some View {
        content
            .refreshable {
                isRefreshing = true
                defer { isRefreshing = false }
                await action()
            }
            .overlay(alignment: .top) {
                if isRefreshing {
                    PlinxLoadingIndicator(
                        size: .regular,
                        surface: .glass,
                        accessibilityLabel: "Refreshing",
                        accessibilityIdentifier: "plinx.refresh.indicator"
                    )
                    .scaleEffect(refreshScale)
                    .frame(width: 48, height: 48)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isRefreshing)
            #if os(iOS)
            .background(PlinxRefreshControlProbe())
            #endif
    }

    private var refreshScale: CGFloat {
        #if os(tvOS)
        0.58
        #else
        0.72
        #endif
    }
}

#if os(iOS)
private struct PlinxRefreshControlProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.hideNativeRefreshIndicator()
    }

    final class ProbeView: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            hideNativeRefreshIndicator()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            hideNativeRefreshIndicator()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            hideNativeRefreshIndicator()
        }

        func hideNativeRefreshIndicator() {
            var candidate = superview

            while let view = candidate {
                if let scrollView = view as? UIScrollView,
                   let refreshControl = scrollView.refreshControl {
                    refreshControl.tintColor = .clear
                    refreshControl.isAccessibilityElement = false
                    refreshControl.accessibilityElementsHidden = true
                    return
                }
                candidate = view.superview
            }
        }
    }
}
#endif

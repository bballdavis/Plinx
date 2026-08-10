import SwiftUI

/// The semantic placement of a loading state in the Plinx experience.
public enum PlinxLoadingRole: Sendable, Equatable, CaseIterable {
    /// A full-screen transition, such as launch or session hydration.
    case appTransition
    /// A wait within an established content screen.
    case content
    /// A compact wait embedded in an existing control or row.
    case inline
    /// Buffering or preparation while watching video.
    case playback

    /// The low-level beacon size prescribed for this role.
    public var indicatorSize: PlinxLoadingSize {
        switch self {
        case .appTransition: .hero
        case .content: .regular
        case .playback: .playback
        case .inline: .compact
        }
    }

    /// The low-level surface contrast prescribed for this role.
    public var indicatorSurface: PlinxLoadingSurface {
        switch self {
        case .appTransition, .content: .glass
        case .inline: .transparent
        case .playback: .video
        }
    }

    /// Whether this context presents Plinx's complete loading identity.
    public var usesFullLockup: Bool { self == .appTransition }
}

/// A role-aware loading state composed from Plinx's low-level beacon.
///
/// The caller supplies `LocalizedStringResource` values, preserving the
/// localization table and bundle that own each message. Only app transitions
/// present the complete Plinx lockup; content and playback stay contextual,
/// while inline waits remain logo-free and compact.
public struct PlinxLoadingStateView: View {
    public let role: PlinxLoadingRole
    public let label: LocalizedStringResource?
    public let accessibilityLabel: LocalizedStringResource?
    public let accessibilityIdentifier: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDelayedContentVisible = false

    public init(
        role: PlinxLoadingRole,
        label: LocalizedStringResource? = nil,
        accessibilityLabel: LocalizedStringResource? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.role = role
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
            ?? "plinx.loading.\(role.accessibilityIdentifierComponent)"
    }

    public var body: some View {
        Group {
            if role.presentationDelay > 0, !isDelayedContentVisible {
                Color.clear
                    .accessibilityHidden(true)
            } else {
                loadingContent
                    .transition(.opacity)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .task(id: role) {
            guard role.presentationDelay > 0 else { return }
            try? await Task.sleep(for: .seconds(role.presentationDelay))
            guard !Task.isCancelled else { return }
            if reduceMotion {
                isDelayedContentVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isDelayedContentVisible = true
                }
            }
        }
    }

    @ViewBuilder
    private var loadingContent: some View {
        if role.usesFullLockup {
            appTransitionContent
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { PlinxAmbientBackground(intensity: .hero) }
        } else {
            indicator
        }
    }

    private var indicator: some View {
        PlinxLoadingIndicator(
            size: role.indicatorSize,
            surface: role.indicatorSurface,
            label: label,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: "\(accessibilityIdentifier).beacon"
        )
    }

    private var appTransitionContent: some View {
        VStack(spacing: 24) {
            indicator

            // The canonical app-owned wordmark is composed by the app-level
            // transition wrapper. PlinxUI never approximates that asset with
            // styled text.
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        if let accessibilityLabel { return Text(accessibilityLabel) }
        if let label { return Text(label) }
        return Text("plinx.loading.default", bundle: .module)
    }
}

private extension PlinxLoadingRole {
    var presentationDelay: TimeInterval {
        switch self {
        case .content: 0.18
        case .inline: 0.12
        case .appTransition, .playback: 0
        }
    }

    var accessibilityIdentifierComponent: String {
        switch self {
        case .appTransition: "appTransition"
        case .content: "content"
        case .inline: "inline"
        case .playback: "playback"
        }
    }
}

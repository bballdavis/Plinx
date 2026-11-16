import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// PlinxOnboardingChrome
//
// Shared pieces of the "quiet shell" onboarding: sign-in, profile selection,
// and server selection sit directly on the ambient dark shell (no portal card),
// with left-aligned display type, a three-step progress indicator, and the
// app's liquid-glass action button (`PlinxActionButtonStyle`).
// ─────────────────────────────────────────────────────────────────────────────

/// The three onboarding steps, in order.
enum PlinxOnboardingStep: Int, CaseIterable {
    case connect = 1
    case profile
    case server
}

/// Layout tiers shared by the onboarding screens.
enum PlinxOnboardingLayout: Equatable {
    case compact
    case regular
    case wide
    case expandedLandscape

    init(width: CGFloat, height: CGFloat) {
        #if os(tvOS)
        self = .regular
        #else
        if width >= 780, width > height, height >= 500 {
            self = width >= 980 ? .wide : .expandedLandscape
        } else if width >= 980 {
            self = .wide
        } else if width >= 560 {
            self = .regular
        } else {
            self = .compact
        }
        #endif
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 24
        case .regular: 48
        case .wide: 64
        case .expandedLandscape: 32
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .compact: PlinxBrandLayoutMetrics.signInCompactTitleSize
        case .regular, .wide: PlinxBrandLayoutMetrics.signInExpandedTitleSize
        case .expandedLandscape: 44
        }
    }

    var logoWidth: CGFloat {
        switch self {
        case .compact: PlinxBrandLayoutMetrics.signInCompactLogoWidth
        case .regular, .wide, .expandedLandscape: PlinxBrandLayoutMetrics.signInExpandedLogoWidth
        }
    }

    /// Readable width for single-column onboarding content.
    var contentMaxWidth: CGFloat {
        switch self {
        case .compact: 560
        case .regular: 640
        case .wide, .expandedLandscape: 1_180
        }
    }

    var usesColumns: Bool { self == .wide || self == .expandedLandscape }
}

/// "Step 2 of 3" with a segmented bar; filled segments use the accent.
struct PlinxOnboardingStepIndicator: View {
    let step: PlinxOnboardingStep
    var isExpanded = false

    var body: some View {
        let total = PlinxOnboardingStep.allCases.count
        VStack(alignment: .trailing, spacing: 6) {
            Text("onboarding.step \(step.rawValue) \(total)", tableName: "Plinx")
                .font(.system(isExpanded ? .subheadline : .caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.brandSecondary)

            HStack(spacing: 4) {
                ForEach(PlinxOnboardingStep.allCases, id: \.rawValue) { candidate in
                    Capsule(style: .continuous)
                        .fill(
                            candidate.rawValue <= step.rawValue
                                ? Color.accentColor
                                : Color.white.opacity(0.18)
                        )
                        .frame(width: isExpanded ? 32 : 22, height: isExpanded ? 5 : 4)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.step")
    }
}

/// Accent shield + "Grown-up step" label that precedes Plex authentication.
struct PlinxOnboardingGrownUpEyebrow: View {
    var isExpanded = false

    var body: some View {
        Label {
            Text("signIn.grownUpStep", tableName: "Plinx")
                .font(.system(isExpanded ? .subheadline : .footnote, design: .rounded, weight: .heavy))
                .tracking(0.6)
        } icon: {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: isExpanded ? 18 : 16, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIdentifier("signIn.grownUpStep")
    }
}

/// The "What happens next" summary used beside or below the sign-in action on
/// larger screens.
struct PlinxOnboardingNextStepsCard: View {
    let currentStep: PlinxOnboardingStep
    var isInformationDisabled = false
    let onInformation: () -> Void

    private struct Row: Identifiable {
        let step: PlinxOnboardingStep
        let titleKey: String
        let detailKey: String
        var id: Int { step.rawValue }
    }

    private let rows: [Row] = [
        Row(step: .connect, titleKey: "onboarding.next.connect.title", detailKey: "onboarding.next.connect.detail"),
        Row(step: .profile, titleKey: "onboarding.next.profile.title", detailKey: "onboarding.next.profile.detail"),
        Row(step: .server, titleKey: "onboarding.next.server.title", detailKey: "onboarding.next.server.detail"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Text("onboarding.next.title", tableName: "Plinx")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.brandSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                PlinxSignInInformationButton(action: onInformation)
                    .disabled(isInformationDisabled)
            }

            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 16) {
                    stepBadge(for: row.step)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(row.titleKey), tableName: "Plinx")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(LocalizedStringKey(row.detailKey), tableName: "Plinx")
                            .font(.system(.callout, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.brandSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(PlinxBrand.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.nextSteps")
    }

    @ViewBuilder
    private func stepBadge(for step: PlinxOnboardingStep) -> some View {
        let isCurrent = step == currentStep
        Text(verbatim: "\(step.rawValue)")
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(isCurrent ? PlinxBrand.shell : Color.brandSecondary)
            .frame(width: 36, height: 36)
            .background {
                if isCurrent {
                    Circle().fill(Color.accentColor)
                } else {
                    Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Quiet secondary access to login help and the sample library.
struct PlinxSignInInformationButton: View {
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(isCompact ? .body : .title2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.brandSecondary)
        .accessibilityLabel(Text("signIn.info.title", tableName: "Plinx"))
        .accessibilityHint(Text("signIn.info.hint", tableName: "Plinx"))
        .accessibilityIdentifier("signIn.infoButton")
    }
}

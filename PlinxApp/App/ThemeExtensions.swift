import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// ThemeExtensions
//
// Defines the Plinx brand color tokens used by both PlinxApp and the compiled
// Strimr vendor sources (which import these via the shared module).
//
// brandPrimary    – the decorative underline stripe in section headers (accent)
// brandSecondary  – section header title text (neutral light-gray)
// appBackground   – screen background
//
// The user-selectable accent color is stored in AppStorage under
// "plinx.accentColorName" and applied as a root `.tint()` in PlinxApp.swift.
// This `.tint()` propagates to tab items, toggles, pickers, and buttons
// app-wide without needing to pepper `.tint(...)` everywhere.
// ─────────────────────────────────────────────────────────────────────────────

extension ShapeStyle where Self == Color {
    /// Decorative accent stripe (matches user-selected accent color via Assets).
    static var brandPrimary: Color { .accentColor }
    static var brandPrimaryForeground: Color { Color.white }

    /// Section title text — neutral light-gray (never purple).
    static var brandSecondary: Color { Color(white: 0.82) }
    static var brandSecondaryForeground: Color { Color.white }
}

extension Color {
    static var brandPrimary: Color { .accentColor }
    static var brandPrimaryForeground: Color { Color.white }
    static var brandSecondary: Color { Color(white: 0.82) }
    static var brandSecondaryForeground: Color { Color.white }
    static var appBackground: Color { PlinxBrand.shell }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlinxAccentColor — Stored accent color palette
// ─────────────────────────────────────────────────────────────────────────────

enum PlinxAccentColor: String, CaseIterable, Identifiable {
    case orange, red, blue, green, teal, pink, yellow, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: return .orange
        case .red:    return Color(red: 0.93, green: 0.15, blue: 0.15)
        case .blue:   return Color(red: 0.2, green: 0.5, blue: 0.98)
        case .green:  return Color(red: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0)
        case .teal:   return Color(red: 0.18, green: 0.72, blue: 0.72)
        case .pink:   return Color(red: 0.95, green: 0.35, blue: 0.6)
        case .yellow: return Color(red: 0.98, green: 0.8, blue: 0.1)
        case .purple: return Color(red: 0.6, green: 0.28, blue: 0.98)
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

enum PlinxChromeButtonSizePreference: String, CaseIterable, Identifiable {
    static let storageKey = "plinx.chromeButtonSize"
    static let defaultValue: Self = .medium

    case small, medium, large

    var id: String { rawValue }

    var sideLength: CGFloat {
        switch self {
        case .small:
            return 39
        case .medium:
            return 52
        case .large:
            return 78
        }
    }

    var iconFontSize: CGFloat {
        switch self {
        case .small:
            return 17
        case .medium:
            return 22
        case .large:
            return 30
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small:
            return 12
        case .medium, .large:
            return 14
        }
    }

    var sliderIndex: Double {
        switch self {
        case .small:
            return 0
        case .medium:
            return 1
        case .large:
            return 2
        }
    }

    var localizationKey: String {
        switch self {
        case .small:
            return "settings.appearance.buttons.small"
        case .medium:
            return "settings.appearance.buttons.medium"
        case .large:
            return "settings.appearance.buttons.large"
        }
    }

    var localizedLabel: String {
        NSLocalizedString(localizationKey, tableName: "Plinx", comment: "")
    }

    static func from(sliderIndex: Double) -> Self {
        switch Int(sliderIndex.rounded()) {
        case 0:
            return .small
        case 2:
            return .large
        default:
            return .medium
        }
    }
}

enum PlinxNavigationPreference {
    static let showSearchInMainNavigationStorageKey = "plinx.showSearchInMainNavigation"
    static let defaultShowSearchInMainNavigation = false
}

enum PlinxAnimationPreference {
    static let playfulAnimationsStorageKey = "plinx.playfulAnimationsEnabled"
    static let defaultPlayfulAnimationsEnabled = false
}

struct PlinxChromeButton: View {
    let systemImage: String
    let action: () -> Void

    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue
    @AppStorage(PlinxAnimationPreference.playfulAnimationsStorageKey)
    private var playfulAnimationsEnabled = PlinxAnimationPreference.defaultPlayfulAnimationsEnabled

    @State private var isAnimatingTap = false

    private var sizePreference: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .medium
    }

    private var isBackButton: Bool {
        systemImage == "chevron.left"
    }

    private var usesPlayfulTapAnimation: Bool {
        playfulAnimationsEnabled && isBackButton
    }

    var body: some View {
        Button(action: handleTap) {
            PlinxChromeIconLabel(
                systemImage: systemImage,
                sizePreference: sizePreference,
                rotation: usesPlayfulTapAnimation && isAnimatingTap ? -16 : 0,
                offset: CGSize(
                    width: usesPlayfulTapAnimation && isAnimatingTap ? -7 : 0,
                    height: usesPlayfulTapAnimation && isAnimatingTap ? -2 : 0
                )
            )
        }
        .scaleEffect(usesPlayfulTapAnimation && isAnimatingTap ? 0.9 : 1.0)
        .offset(y: usesPlayfulTapAnimation && isAnimatingTap ? -3 : 0)
        .shadow(
            color: usesPlayfulTapAnimation && isAnimatingTap ? Color.accentColor.opacity(0.22) : .clear,
            radius: usesPlayfulTapAnimation && isAnimatingTap ? 16 : 0,
            y: usesPlayfulTapAnimation && isAnimatingTap ? 8 : 0
        )
        .animation(.easeOut(duration: 0.2), value: isAnimatingTap)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text("accessibility.chromeButton.hint", tableName: "Plinx"))
    }

    private var accessibilityLabel: Text {
        let key: String
        switch systemImage {
        case "chevron.left":
            key = "common.actions.back"
        case "xmark":
            key = "common.actions.close"
        case "gearshape.fill":
            key = "tabs.settings"
        case "magnifyingglass":
            key = "tabs.search"
        case "tray.full":
            key = "youtarr.requests.title"
        case "rectangle.portrait.and.arrow.right":
            key = "common.actions.logOut"
        default:
            key = "accessibility.chromeButton.action"
        }
        return Text(LocalizedStringKey(key), tableName: "Plinx")
    }

    private func handleTap() {
        guard usesPlayfulTapAnimation else {
            action()
            return
        }

        guard !isAnimatingTap else { return }

        isAnimatingTap = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            action()
            isAnimatingTap = false
        }
    }
}

struct PlinxChromeIconLabel: View {
    let systemImage: String
    let sizePreference: PlinxChromeButtonSizePreference
    var rotation: Double = 0
    var offset: CGSize = .zero

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: sizePreference.iconFontSize, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .rotationEffect(.degrees(rotation))
            .offset(x: offset.width, y: offset.height)
            .frame(width: sizePreference.sideLength, height: sizePreference.sideLength)
            .background(
                RoundedRectangle(cornerRadius: sizePreference.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: sizePreference.cornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
    }
}

/// A labeled companion to `PlinxChromeButton` for retry and other compact
/// actions that need the same liquid-glass navigation treatment.
struct PlinxChromeActionButton: View {
    let titleKey: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(titleKey), tableName: "Plinx")
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(PlinkButtonStyle())
        .accessibilityHint(Text("accessibility.chromeButton.hint", tableName: "Plinx"))
    }
}

/// Keeps the tvOS focus ring attached to the scaled artwork edge.
///
/// The ring is expanded by half its width before the combined artwork/ring is
/// scaled. That leaves the full thumbnail unobscured and prevents the inset
/// border that appears when a ring is applied after `scaleEffect`.
struct PlinxTVCardFocusArtworkModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    let focusedScale: CGFloat
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .overlay {
                shape
                    .stroke(isFocused ? Color.accentColor : .clear, lineWidth: lineWidth)
                    .padding(-(lineWidth / 2))
            }
            .shadow(
                color: isFocused ? Color.accentColor.opacity(0.58) : .clear,
                radius: isFocused ? 10 : 0
            )
            .shadow(
                color: isFocused ? Color.accentColor.opacity(0.22) : .clear,
                radius: isFocused ? 18 : 0
            )
            .scaleEffect(isFocused && !reduceMotion ? focusedScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
    }
}

extension View {
    func plinxTVCardFocusArtwork(
        isFocused: Bool,
        cornerRadius: CGFloat,
        focusedScale: CGFloat = 1.08,
        lineWidth: CGFloat = 4
    ) -> some View {
        modifier(
            PlinxTVCardFocusArtworkModifier(
                isFocused: isFocused,
                cornerRadius: cornerRadius,
                focusedScale: focusedScale,
                lineWidth: lineWidth
            )
        )
    }
}

/// Shared Plinx chrome for the primary and secondary actions in media detail.
/// The paired Strimr views compile into the app target, so this keeps their
/// product-specific presentation in Plinx without forking their behavior.

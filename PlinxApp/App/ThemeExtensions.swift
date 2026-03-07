import SwiftUI

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
    static var appBackground: Color { Color(red: 0.05, green: 0.05, blue: 0.08) }
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

struct PlinxChromeButton: View {
    let systemImage: String
    let action: () -> Void

    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue

    private var sizePreference: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .medium
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: sizePreference.iconFontSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
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
        .buttonStyle(.plain)
    }
}

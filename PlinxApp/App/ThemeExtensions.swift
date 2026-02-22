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
        case .green:  return Color(red: 0.2, green: 0.78, blue: 0.35)
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

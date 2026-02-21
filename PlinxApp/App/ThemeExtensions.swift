import SwiftUI

extension ShapeStyle where Self == Color {
    static var brandPrimary: Color { Color.blue }
    static var brandPrimaryForeground: Color { Color.white }
    static var brandSecondary: Color { Color.purple }
    static var brandSecondaryForeground: Color { Color.white }
}

extension Color {
    static var brandPrimary: Color { Color.blue }
    static var brandPrimaryForeground: Color { Color.white }
    static var brandSecondary: Color { Color.purple }
    static var brandSecondaryForeground: Color { Color.white }
    static var appBackground: Color { Color(red: 0.05, green: 0.05, blue: 0.08) }
}

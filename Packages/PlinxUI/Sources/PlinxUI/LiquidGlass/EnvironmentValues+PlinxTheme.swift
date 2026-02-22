import SwiftUI

private struct PlinxThemeKey: EnvironmentKey {
    static let defaultValue = PlinxTheme()
}

public extension EnvironmentValues {
    var plinxTheme: PlinxTheme {
        get { self[PlinxThemeKey.self] }
        set { self[PlinxThemeKey.self] = newValue }
    }
}

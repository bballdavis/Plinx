import SwiftUI
import PlinxUI

#if os(tvOS)
/// Owns the active Settings destination stack for tvOS Menu handling.
///
/// SwiftUI may deliver one Menu command to both a focused destination and its
/// enclosing shell. Routing the command through one stack guarantees exactly
/// one pop before the gated Settings experience is allowed to close.
final class PlinxSettingsNavigationCoordinator {
    private struct Destination {
        let id: UUID
        let dismiss: DismissAction
    }

    private var destinations: [Destination] = []

    func register(id: UUID, dismiss: DismissAction) {
        destinations.removeAll { $0.id == id }
        destinations.append(Destination(id: id, dismiss: dismiss))
    }

    func unregister(id: UUID) {
        destinations.removeAll { $0.id == id }
    }

    @discardableResult
    func dismissTopDestination() -> Bool {
        guard let destination = destinations.last else { return false }
        destination.dismiss()
        return true
    }
}

private struct PlinxSettingsNavigationCoordinatorKey: EnvironmentKey {
    static let defaultValue: PlinxSettingsNavigationCoordinator? = nil
}

extension EnvironmentValues {
    var plinxSettingsNavigationCoordinator: PlinxSettingsNavigationCoordinator? {
        get { self[PlinxSettingsNavigationCoordinatorKey.self] }
        set { self[PlinxSettingsNavigationCoordinatorKey.self] = newValue }
    }
}
#endif

/// Shared visual shell for parent-only settings pages.
///
/// Navigation remains platform-native: iOS/iPad keep their navigation bars and
/// grouped lists, while tvOS inherits the single persistent branded shell from
/// `RootTabView` and uses this modifier only for the ambient surface.
struct PlinxSettingsChrome: ViewModifier {
    let handlesExit: Bool
    @Environment(\.dismiss) private var dismiss
    #if os(tvOS)
    @Environment(\.plinxSettingsNavigationCoordinator) private var navigationCoordinator
    @State private var destinationID = UUID()
    #endif

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        if handlesExit {
            if let navigationCoordinator {
                settingsDestinationSurface(content)
                    .onAppear {
                        navigationCoordinator.register(id: destinationID, dismiss: dismiss)
                    }
                    .onDisappear {
                        navigationCoordinator.unregister(id: destinationID)
                    }
            } else {
                settingsDestinationSurface(content)
                    .onExitCommand {
                        dismiss()
                    }
            }
        } else {
            settingsSurface(content)
        }
        #else
        content
            .scrollContentBackground(.hidden)
            .background(PlinxAmbientBackground(intensity: .restrained))
        #endif
    }

    #if os(tvOS)
    private func settingsSurface(_ content: Content) -> some View {
        content
            .background(PlinxAmbientBackground(intensity: .restrained))
            .tint(.accentColor)
            .buttonStyle(PlinxSettingsListButtonStyle())
            .toggleStyle(PlinxSettingsToggleStyle())
            .textFieldStyle(PlinxSettingsTextFieldStyle())
    }

    private func settingsDestinationSurface(_ content: Content) -> some View {
        settingsSurface(content)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label {
                            Text("common.actions.back", tableName: "Plinx")
                        } icon: {
                            Image(systemName: "chevron.left")
                        }
                    }
                    .buttonStyle(PlinxSettingsActionButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityIdentifier("settings.back")

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 42)
                .padding(.top, PlinxTVShellMetrics.contentClearance + 12)
                .padding(.bottom, 14)
                .background(
                    LinearGradient(
                        colors: [Color.appBackground, Color.appBackground.opacity(0.94), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
    }
    #endif
}

extension View {
    /// Applies parent-only Settings chrome. On tvOS, subpages also consume one
    /// Menu press to pop themselves. The Settings root opts out so its shell can
    /// close the gated experience only after the navigation stack is at root.
    func plinxSettingsChrome(handlesExit: Bool = true) -> some View {
        modifier(PlinxSettingsChrome(handlesExit: handlesExit))
    }
}

#if os(tvOS)
extension PlinxFocusSurfaceStyle {
    /// The stable Settings focus treatment keeps tvOS from applying its own
    /// bright focus plate while preserving each control's native geometry.
    static func tvSettings(cornerRadius: CGFloat) -> Self {
        Self(
            selectionOpacity: 0.72,
            focusRingOpacity: 0.98,
            focusedScale: 1,
            focusedShadowRadius: 10,
            cornerRadius: cornerRadius,
            focusedFillOpacity: 0.14
        )
    }
}

struct PlinxSettingsActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlinxSettingsActionButtonBody(configuration: configuration)
    }
}

/// Default row treatment for tvOS Settings destinations. Native tvOS List and
/// Form controls otherwise introduce a bright white focus plate that conflicts
/// with the accent ring used by the Settings root and rating chooser.
struct PlinxSettingsListButtonStyle: ButtonStyle {
    var isSelected = false
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        PlinxSettingsListButtonBody(
            configuration: configuration,
            isSelected: isSelected,
            cornerRadius: cornerRadius
        )
    }
}

private struct PlinxSettingsListButtonBody: View {
    let configuration: PlinxSettingsListButtonStyle.Configuration
    let isSelected: Bool
    let cornerRadius: CGFloat

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .plinxFocusSurface(
                isSelected: isSelected,
                isFocused: isFocused,
                style: .tvSettings(cornerRadius: cornerRadius)
            )
            .focusEffectDisabled()
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct PlinxSettingsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        PlinxSettingsTextFieldBody(configuration: configuration)
    }
}

private struct PlinxSettingsTextFieldBody<Label: View>: View {
    let configuration: TextField<Label>

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration
            .padding(.horizontal, 20)
            .frame(minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .plinxFocusSurface(
                isSelected: false,
                isFocused: isFocused,
                style: .tvSettings(cornerRadius: 16)
            )
            .focusEffectDisabled()
    }
}

struct PlinxSettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 18) {
                configuration.label
                Spacer(minLength: 18)
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.white.opacity(0.58))
            }
        }
        .buttonStyle(PlinxSettingsListButtonStyle(isSelected: configuration.isOn))
        .focusEffectDisabled()
        .accessibilityValue(
            Text(configuration.isOn ? "common.status.on" : "common.status.off", tableName: "Plinx")
        )
    }
}

extension View {
    func plinxSettingsListButton(isSelected: Bool = false, cornerRadius: CGFloat = 18) -> some View {
        buttonStyle(
            PlinxSettingsListButtonStyle(
                isSelected: isSelected,
                cornerRadius: cornerRadius
            )
        )
        .focusEffectDisabled()
    }
}

private struct PlinxSettingsActionButtonBody: View {
    let configuration: PlinxSettingsActionButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .plinxFocusSurface(
                isSelected: false,
                isFocused: isFocused,
                style: .tvSettings(cornerRadius: 16)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
#endif

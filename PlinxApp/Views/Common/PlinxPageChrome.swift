import SwiftUI
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// PlinxPageChrome
//
// Shared header and page scaffolding so pushed screens, settings subpages and
// sheets use the same liquid-glass chrome instead of the system navigation bar,
// system back button, system picker menus, or stock grouped-list backgrounds.
//
// Header geometry is the app-wide standard: 20 pt horizontal, 8 pt top and
// 10 pt bottom padding, with `PlinxChromeButton` controls.
// ─────────────────────────────────────────────────────────────────────────────

enum PlinxPageHeaderMetrics {
    #if os(tvOS)
    static let horizontalPadding: CGFloat = 42
    static let topPadding: CGFloat = 26
    static let bottomPadding: CGFloat = 20
    #else
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 10
    #endif
}

/// A header row with an optional leading back button, a centered title and
/// optional trailing chrome actions.
struct PlinxPageHeader<Trailing: View>: View {
    let title: Text?
    let onBack: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue

    /// Keeps a centered title clear of a chrome button on each side.
    private var titleInset: CGFloat {
        let size = PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .defaultValue
        return size.sideLength + 16
    }

    init(
        title: Text?,
        onBack: (() -> Void)?,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            if let title {
                title
                    #if os(tvOS)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    #else
                    .font(.title3.weight(.bold))
                    #endif
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, titleInset)
                    .accessibilityAddTraits(.isHeader)
            }

            HStack(spacing: 12) {
                if let onBack {
                    PlinxChromeButton(systemImage: "chevron.left", action: onBack)
                }
                Spacer(minLength: 0)
                trailing()
            }
        }
        .padding(.horizontal, PlinxPageHeaderMetrics.horizontalPadding)
        .padding(.top, PlinxPageHeaderMetrics.topPadding)
        .padding(.bottom, PlinxPageHeaderMetrics.bottomPadding)
    }
}

extension PlinxPageHeader where Trailing == EmptyView {
    init(title: Text?, onBack: (() -> Void)?) {
        self.init(title: title, onBack: onBack) { EmptyView() }
    }
}

/// A sheet header: leading title and a trailing close button, matching the
/// root settings sheet.
struct PlinxSheetHeader<Leading: View>: View {
    let title: Text
    let onClose: () -> Void
    @ViewBuilder let leading: () -> Leading

    init(
        title: Text,
        onClose: @escaping () -> Void,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.title = title
        self.onClose = onClose
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 12) {
            leading()
            title
                #if os(tvOS)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                #else
                .font(.title3.weight(.bold))
                #endif
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            PlinxChromeButton(systemImage: "xmark", action: onClose)
        }
        .padding(.horizontal, PlinxPageHeaderMetrics.horizontalPadding)
        .padding(.top, PlinxPageHeaderMetrics.topPadding)
        .padding(.bottom, PlinxPageHeaderMetrics.bottomPadding)
    }
}

extension PlinxSheetHeader where Leading == EmptyView {
    init(title: Text, onClose: @escaping () -> Void) {
        self.init(title: title, onClose: onClose) { EmptyView() }
    }
}

// MARK: - Pushed page chrome

private struct PlinxPushedPageChrome: ViewModifier {
    let title: Text?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                PlinxPageHeader(title: title, onBack: { dismiss() })
            }
    }
}

// MARK: - Settings page chrome

private struct PlinxSettingsPageChrome: ViewModifier {
    let title: Text

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .listStyle(.plain)
            .navigationTitle(title)
            .background(Color.appBackground.ignoresSafeArea())
        #else
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .tint(.accentColor)
            .modifier(PlinxPushedPageChrome(title: title))
        #endif
    }
}

extension View {
    /// Replaces the system navigation bar on a pushed screen with the Plinx
    /// back button and centered title.
    func plinxPushedPageChrome(title: Text?) -> some View {
        modifier(PlinxPushedPageChrome(title: title))
    }

    /// Applies the shared settings-subpage treatment: dark shell background,
    /// inset grouped rows, accent tint and the Plinx back-button header.
    func plinxSettingsPage(title: Text) -> some View {
        modifier(PlinxSettingsPageChrome(title: title))
    }
}

// MARK: - Settings choice list

/// One selectable value in a `PlinxSettingsChoiceView`.
struct PlinxSettingsChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var detail: String? = nil

    var id: Value { value }
}

/// A Plinx-styled replacement for `Picker` with `.menu` or `.navigationLink`
/// styles, which otherwise open stock system menus and pushed lists.
struct PlinxSettingsChoiceView<Value: Hashable>: View {
    let title: Text
    let choices: [PlinxSettingsChoice<Value>]
    @Binding var selection: Value
    var footer: Text? = nil
    var accessibilityPrefix: String = "settings.choice"

    var body: some View {
        List {
            Section {
                ForEach(choices) { choice in
                    Button {
                        selection = choice.value
                    } label: {
                        PlinxSettingsChoiceRow(
                            title: choice.title,
                            detail: choice.detail,
                            isSelected: choice.value == selection
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(accessibilityPrefix).\(choice.id)")
                    .accessibilityAddTraits(choice.value == selection ? .isSelected : [])
                }
            } footer: {
                if let footer {
                    footer
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .plinxSettingsPage(title: title)
    }
}

private struct PlinxSettingsChoiceRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Spacer(minLength: 12)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.3))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// A settings row label that shows the current value on the trailing edge,
/// used as the `NavigationLink` label for a `PlinxSettingsChoiceView`.
struct PlinxSettingsValueLabel: View {
    let title: Text
    let systemImage: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
    }
}

// MARK: - Buttons

/// Accent-filled primary action for forms inside Plinx surfaces. Replaces
/// `.borderedProminent`, which renders as a stock system capsule.
struct PlinxPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlinxPrimaryActionButtonBody(configuration: configuration)
    }
}

private struct PlinxPrimaryActionButtonBody: View {
    let configuration: PlinxPrimaryActionButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(isEnabled ? 1 : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.7)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Action panel

/// One action in a `PlinxActionPanel`.
struct PlinxActionPanelOption: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isEnabled: Bool = true
    let action: () -> Void
}

/// A liquid-glass bottom panel matching the home screen's long-press quick
/// actions. Use it instead of `.confirmationDialog`, which renders a stock
/// system action sheet. Width is capped so it stays a compact panel on iPad.
struct PlinxActionPanel: View {
    static let maximumWidth: CGFloat = 560

    let title: String
    let options: [PlinxActionPanelOption]
    let onCancel: () -> Void
    var accessibilityPrefix: String = "actionPanel"

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityIdentifier("\(accessibilityPrefix).backdrop")

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                ForEach(options) { option in
                    Button(action: option.action) {
                        HStack(spacing: 10) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white.opacity(option.isEnabled ? 0.95 : 0.5))
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor.opacity(option.isEnabled ? 0.18 : 0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.accentColor.opacity(option.isEnabled ? 0.32 : 0.12), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PlinkButtonStyle())
                    .disabled(!option.isEnabled)
                    .accessibilityIdentifier("\(accessibilityPrefix).option.\(option.id)")
                }

                Button(action: onCancel) {
                    Text("common.actions.cancel", tableName: "Plinx")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityPrefix).cancel")
            }
            .padding(14)
            .liquidGlassBackground(style: PlinxTheme.Glass(cornerRadius: 14))
            .frame(maxWidth: Self.maximumWidth)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(accessibilityPrefix).sheet")
        }
    }
}

// MARK: - Compact destructive control

/// A compact glass control for destructive account actions such as Log Out.
/// It replaces the stock toolbar icon while staying smaller than the shell's
/// chrome buttons so it never reads as a primary kid-facing action.
struct PlinxCompactDestructiveButton: View {
    let systemImage: String
    let accessibilityLabel: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

import PlinxUI
import SwiftUI

struct PlinxQuickActionOption: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void
}

/// Shared, surface-local quick-action presentation.
///
/// Presentation ownership stays with the calling screen while menu focus and
/// dismissal behavior remain identical in the root, detail, and player flows.
struct PlinxQuickActionMenu: View {
    let title: String
    let options: [PlinxQuickActionOption]
    let onDismiss: () -> Void

    #if os(tvOS)
    @FocusState private var focusedID: String?
    #endif

    private var cornerRadius: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }

    private var optionMinHeight: CGFloat {
        #if os(tvOS)
        78
        #else
        52
        #endif
    }

    private var cancelMinHeight: CGFloat {
        #if os(tvOS)
        75
        #else
        50
        #endif
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        21
        #else
        14
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityIdentifier("quickAction.backdrop")
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 12) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("quickAction.sheet")

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                ForEach(options) { option in
                    optionButton(option)
                }

                cancelButton
            }
            .padding(14)
            .liquidGlassBackground(style: PlinxTheme.Glass(cornerRadius: cornerRadius))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            #if os(tvOS)
            .focusSection()
            #endif
        }
        #if os(tvOS)
        .onAppear {
            focusedID = options.first?.id ?? QuickActionFocusOrder.cancelID
        }
        .onDisappear { focusedID = nil }
        .onPlayPauseCommand(perform: activateFocusedOption)
        .onExitCommand(perform: onDismiss)
        #endif
    }

    private func optionButton(_ option: PlinxQuickActionOption) -> some View {
        #if os(tvOS)
        let isFocused = focusedID == option.id
        #else
        let isFocused = false
        #endif

        return Button(role: option.role) {
            onDismiss()
            option.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: optionMinHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PlinxBrand.surface.opacity(isFocused ? 1 : 0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
            )
            .plinxFocusSurface(
                isSelected: false,
                isFocused: isFocused,
                style: PlinxFocusSurfaceStyle(focusedScale: 1, cornerRadius: cornerRadius)
            )
        }
        .buttonStyle(PlinkButtonStyle())
        #if os(tvOS)
        .focusEffectDisabled()
        .focused($focusedID, equals: option.id)
        #endif
        .accessibilityIdentifier("quickAction.option.\(option.id)")
    }

    private var cancelButton: some View {
        #if os(tvOS)
        let isFocused = focusedID == QuickActionFocusOrder.cancelID
        #else
        let isFocused = false
        #endif

        return Button(action: onDismiss) {
            Text(String(localized: "common.actions.cancel"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, minHeight: cancelMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(PlinxBrand.surface.opacity(isFocused ? 1 : 0.9))
                )
                .plinxFocusSurface(
                    isSelected: false,
                    isFocused: isFocused,
                    style: PlinxFocusSurfaceStyle(focusedScale: 1, cornerRadius: cornerRadius)
                )
        }
        .buttonStyle(PlinkButtonStyle())
        #if os(tvOS)
        .focusEffectDisabled()
        .focused($focusedID, equals: QuickActionFocusOrder.cancelID)
        #endif
        .accessibilityIdentifier("quickAction.cancel")
    }

    #if os(tvOS)
    private func activateFocusedOption() {
        guard let focusedID else { return }
        if focusedID == QuickActionFocusOrder.cancelID {
            onDismiss()
            return
        }
        guard let option = options.first(where: { $0.id == focusedID }) else { return }
        onDismiss()
        option.action()
    }
    #endif
}

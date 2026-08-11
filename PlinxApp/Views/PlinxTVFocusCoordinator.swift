import Combine
import Foundation
#if os(tvOS)
import PlinxUI
import SwiftUI
import UIKit
#endif

/// Every focusable destination in the persistent Apple TV shell.
///
/// Settings is deliberately represented as a real target rather than a tab
/// with a nil coordinator destination, which makes focus restoration
/// deterministic before and after the parental gate.
enum PlinxTVShellFocusTarget: Hashable {
    case tab(MainCoordinator.Tab)
    case settings
}

/// Coarse content ownership used when the shell hands focus back to the
/// currently visible screen.
enum PlinxTVContentRegion: Hashable {
    case home
    case search
    case library
    case libraryDetail
    case detail
    case settings
    case other
}

struct PlinxTVFocusRestoration: Equatable {
    let contentRegion: PlinxTVContentRegion
    let shellTarget: PlinxTVShellFocusTarget?
}

/// Owns the small amount of focus state shared across the persistent tvOS
/// shell. Individual screens continue to own their concrete card/row focus.
@MainActor
final class PlinxTVFocusCoordinator: ObservableObject {
    @Published private(set) var activeContentRegion: PlinxTVContentRegion = .home
    @Published private(set) var contentFocusRequest = 0

    private var lastContentTargetByRegion: [PlinxTVContentRegion: AnyHashable] = [:]
    private var modalRestorationStack: [PlinxTVFocusRestoration] = []

    func activate(_ region: PlinxTVContentRegion) {
        activeContentRegion = region
    }

    func requestContentFocus() {
        contentFocusRequest &+= 1
    }

    func rememberContentTarget<ID: Hashable>(_ target: ID, in region: PlinxTVContentRegion) {
        lastContentTargetByRegion[region] = AnyHashable(target)
    }

    func rememberedContentTarget<ID: Hashable>(
        in region: PlinxTVContentRegion,
        availableIDs: [ID]
    ) -> ID? {
        guard let remembered = lastContentTargetByRegion[region]?.base as? ID,
              availableIDs.contains(remembered) else {
            return nil
        }
        return remembered
    }

    func beginModal(from region: PlinxTVContentRegion, shellTarget: PlinxTVShellFocusTarget?) {
        modalRestorationStack.append(
            PlinxTVFocusRestoration(contentRegion: region, shellTarget: shellTarget)
        )
    }

    func endModal() -> PlinxTVFocusRestoration? {
        modalRestorationStack.popLast()
    }

    func shellTarget(
        activeTab: MainCoordinator.Tab,
        showsSettings: Bool,
        visibleTabs: [KidsMainTabPicker.TabItem]
    ) -> PlinxTVShellFocusTarget? {
        if showsSettings,
           visibleTabs.contains(where: { $0.action == .settings }) {
            return .settings
        }

        if visibleTabs.contains(where: { $0.tab == activeTab }) {
            return .tab(activeTab)
        }

        return visibleTabs.compactMap(\.tab).first.map(PlinxTVShellFocusTarget.tab)
    }

    /// Keeps a still-valid content target, otherwise falls back in a stable
    /// order: preferred target, then the first available target.
    nonisolated static func resolvedContentID<ID: Hashable>(
        currentID: ID?,
        availableIDs: [ID],
        preferredID: ID? = nil
    ) -> ID? {
        if let currentID, availableIDs.contains(currentID) {
            return currentID
        }
        if let preferredID, availableIDs.contains(preferredID) {
            return preferredID
        }
        return availableIDs.first
    }

    /// Resolves a removed target to the closest surviving sibling from the
    /// previous ordering before falling back to a preferred or first target.
    nonisolated static func resolvedContentID<ID: Hashable>(
        currentID: ID?,
        previousIDs: [ID],
        availableIDs: [ID],
        preferredID: ID? = nil
    ) -> ID? {
        if let currentID, availableIDs.contains(currentID) {
            return currentID
        }

        if let currentID, let removedIndex = previousIDs.firstIndex(of: currentID) {
            for distance in 1...max(previousIDs.count, 1) {
                let candidates = [removedIndex + distance, removedIndex - distance]
                for index in candidates where previousIDs.indices.contains(index) {
                    let candidate = previousIDs[index]
                    if availableIDs.contains(candidate) {
                        return candidate
                    }
                }
            }
        }

        return resolvedContentID(
            currentID: nil,
            availableIDs: availableIDs,
            preferredID: preferredID
        )
    }
}

#if os(tvOS)
/// A deliberately unstyled tvOS text control. SwiftUI's tvOS `TextField`
/// paints an opaque white editing plate even when `.plain` and
/// `focusEffectDisabled()` are applied. Hosting `UITextField` directly lets
/// Plinx own the one visible rounded surface around the entry control.
struct PlinxTVTextEntry: View {
    enum SubmitKind {
        case done
        case search
    }

    @Binding var text: String
    let placeholder: String
    var isSecure = false
    var submitKind: SubmitKind = .done
    var showsSurface = false
    var onTextChange: () -> Void = {}
    var onSubmit: () -> Void = {}

    @State private var isNativeFocused = false

    var body: some View {
        if showsSurface {
            entryContent
                .padding(.horizontal, 20)
                .frame(minHeight: 68)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PlinxBrand.surface.opacity(0.98))
                )
                .plinxFocusSurface(
                    isSelected: false,
                    isFocused: isNativeFocused,
                    style: PlinxFocusSurfaceStyle(
                        selectionOpacity: 0.72,
                        focusRingOpacity: 0.98,
                        focusedScale: 1,
                        focusedShadowRadius: 10,
                        cornerRadius: 16,
                        focusedFillOpacity: 0.14
                    )
                )
        } else {
            entryContent
        }
    }

    private var entryContent: some View {
        ZStack(alignment: .leading) {
            PlinxTVNativeTextEntry(
                text: $text,
                placeholder: placeholder,
                isSecure: isSecure,
                submitKind: submitKind,
                onTextChange: onTextChange,
                onSubmit: onSubmit,
                onFocusChange: { isNativeFocused = $0 }
            )
            // UIKit excludes views at or below 0.01 alpha from geometric focus.
            // This remains visually transparent while allowing Siri Remote
            // navigation to discover the native keyboard control.
            .opacity(0.011)

            Text(displayText)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(text.isEmpty ? .white.opacity(0.52) : .white)
                .lineLimit(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
    }

    private var displayText: String {
        guard !text.isEmpty else { return placeholder }
        return isSecure ? String(repeating: "•", count: text.count) : text
    }
}

private struct PlinxTVNativeTextEntry: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    let submitKind: PlinxTVTextEntry.SubmitKind
    let onTextChange: () -> Void
    let onSubmit: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ClearTVTextField {
        let textField = ClearTVTextField()
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        textField.onFocusChange = onFocusChange
        configure(textField)
        return textField
    }

    func updateUIView(_ textField: ClearTVTextField, context: Context) {
        context.coordinator.parent = self
        textField.onFocusChange = onFocusChange
        if textField.text != text {
            textField.text = text
        }
        configure(textField)
    }

    private func configure(_ textField: ClearTVTextField) {
        textField.isSecureTextEntry = isSecure
        textField.returnKeyType = submitKind == .search ? .search : .done
        textField.textColor = .white
        textField.tintColor = UIColor(PlinxBrand.teal)
        textField.font = .systemFont(ofSize: 30, weight: .medium)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.52)]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PlinxTVNativeTextEntry

        init(parent: PlinxTVNativeTextEntry) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
            parent.onTextChange()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }
}

final class ClearTVTextField: UITextField {
    var onFocusChange: (Bool) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        borderStyle = .none
        background = nil
        disabledBackground = nil
        backgroundColor = .clear
        layer.backgroundColor = UIColor.clear.cgColor
        clearButtonMode = .never
        autocorrectionType = .no
        autocapitalizationType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        background = nil
        backgroundColor = .clear
        layer.backgroundColor = UIColor.clear.cgColor
        onFocusChange(isFocused)
    }
}
#endif

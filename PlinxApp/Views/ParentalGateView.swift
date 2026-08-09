import SwiftUI
import UIKit
import PlinxCore
import PlinxUI

struct ParentalGateView: View {
    @Environment(ParentalAccessCoordinator.self) private var parentalAccessCoordinator

    // Math gate state
    @State private var challenge: MathGate.Challenge
    @State private var answerText = ""
    private var mathGate = MathGate()

    // PIN gate state
    @State private var pinEntry = ""
    @State private var pinError = false
    @State private var lockoutMessage: String?

    var onAllowed: () -> Void

    init(onAllowed: @escaping () -> Void) {
        var rng = SystemRandomNumberGenerator()
        _challenge = State(initialValue: mathGate.makeChallenge(rng: &rng))
        self.onAllowed = onAllowed
    }

    private var usePIN: Bool { parentalAccessCoordinator.hasPIN }
    private let entryFieldSize = CGSize(width: 100, height: 32)
    private let entryFieldSlotHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: 24) {
            PlinxBrandLogoView(
                asset: .stackedOnGradient,
                accessibilityIdentifier: "parentalGate.logo",
                maxWidth: 176
            )
            .frame(height: 200)

            if usePIN {
                pinChallengeView
            } else {
                mathChallengeView
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PlinxBrand.gradient
                .ignoresSafeArea()
        }
    }

    // MARK: - PIN gate

    private var pinChallengeView: some View {
        VStack(spacing: 20) {
            Text("parental.gate.pin.title", tableName: "Plinx")
                .font(.title2.bold())
                .foregroundStyle(PlinxBrand.shell)
                .accessibilityIdentifier("parentalGate.title")
                .accessibilityValue(PlinxBrandingSemantics.parentalGateTitleColorValue)

            Group {
                #if os(tvOS)
                TvParentalNumberPad(
                    text: $pinEntry,
                    isSecure: true,
                    maximumDigits: 6,
                    accessibilityLabel: NSLocalizedString(
                        "parental.gate.pin.accessibilityLabel",
                        tableName: "Plinx",
                        comment: ""
                    ),
                    onSubmit: submitPin
                )
                #else
                NumberPadEntryField(
                    text: $pinEntry,
                    placeholder: "",
                    isSecure: true,
                    maximumDigits: 6,
                    accessibilityLabel: NSLocalizedString(
                        "parental.gate.pin.accessibilityLabel",
                        tableName: "Plinx",
                        comment: ""
                    ),
                    onSubmit: submitPin
                )
                .frame(width: entryFieldSize.width, height: entryFieldSize.height)
                .frame(maxWidth: .infinity, minHeight: entryFieldSlotHeight, maxHeight: entryFieldSlotHeight, alignment: .center)
                #endif
            }
            .onChange(of: pinEntry) { _, _ in
                pinError = false
            }

            if pinError {
                Text("parental.gate.pin.wrong", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let lockoutMessage {
                Text(lockoutMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            #if !os(tvOS)
            unlockButton(action: submitPin)
            #endif
        }
    }

    // MARK: - Math gate

    private var mathChallengeView: some View {
        VStack(spacing: 20) {
            Text("parental.gate.title", tableName: "Plinx")
                .font(.title2.bold())
                .foregroundStyle(PlinxBrand.shell)
                .accessibilityIdentifier("parentalGate.title")
                .accessibilityValue(PlinxBrandingSemantics.parentalGateTitleColorValue)

            Text(challenge.prompt)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(PlinxBrand.shell)
                .accessibilityIdentifier("parentalGate.challenge")

            #if os(tvOS)
            TvParentalNumberPad(
                text: $answerText,
                isSecure: false,
                maximumDigits: 4,
                accessibilityLabel: NSLocalizedString(
                    "parental.gate.answer.accessibilityLabel",
                    tableName: "Plinx",
                    comment: ""
                ),
                onSubmit: submitMathAnswer
            )
            #else
            NumberPadEntryField(
                text: $answerText,
                placeholder: NSLocalizedString("parental.gate.placeholder", tableName: "Plinx", comment: ""),
                accessibilityLabel: NSLocalizedString(
                    "parental.gate.answer.accessibilityLabel",
                    tableName: "Plinx",
                    comment: ""
                ),
                onSubmit: submitMathAnswer
            )
                .frame(width: entryFieldSize.width, height: entryFieldSize.height)
                .frame(maxWidth: .infinity, minHeight: entryFieldSlotHeight, maxHeight: entryFieldSlotHeight, alignment: .center)
            #endif

            #if !os(tvOS)
            unlockButton(action: submitMathAnswer)
            #endif
        }
    }

    private func unlockButton(action: @escaping () -> Void) -> some View {
        LiquidGlassButton(
            LocalizedStringResource("parental.gate.unlock", table: "Plinx"),
            treatment: .brand,
            action: action
        )
        .accessibilityIdentifier("parentalGate.unlock")
        .accessibilityValue(PlinxBrandingSemantics.parentalGateUnlockStyleValue)
    }
}

extension ParentalGateView {
    private func submitPin() {
        pinError = false
        lockoutMessage = nil
        switch parentalAccessCoordinator.unlock(withPIN: pinEntry) {
        case .allowed:
            onAllowed()
        case .denied:
            pinError = true
            pinEntry = ""
            UIAccessibility.post(
                notification: .announcement,
                argument: NSLocalizedString("parental.gate.pin.wrong", tableName: "Plinx", comment: "")
            )
        case .lockedOut:
            pinEntry = ""
            lockoutMessage = NSLocalizedString(
                "parental.gate.pin.lockedOut",
                tableName: "Plinx",
                comment: ""
            )
            UIAccessibility.post(notification: .announcement, argument: lockoutMessage)
        case .unavailable:
            pinEntry = ""
        }
    }

    private func submitMathAnswer() {
        if let answer = Int(answerText), mathGate.validate(answer: answer, for: challenge) {
            if parentalAccessCoordinator.unlockWithMathChallenge() == .allowed {
                onAllowed()
            }
        } else {
            var rng = SystemRandomNumberGenerator()
            challenge = mathGate.makeChallenge(rng: &rng)
            answerText = ""
        }
    }
}

#if os(tvOS)
private struct TvParentalNumberPad: View {
    private enum Key: Hashable {
        case digit(Int)
        case delete
        case unlock
    }

    @Binding var text: String
    let isSecure: Bool
    let maximumDigits: Int
    let accessibilityLabel: String
    let onSubmit: () -> Void

    @FocusState private var focusedKey: Key?

    private let columns = Array(repeating: GridItem(.fixed(150), spacing: 14), count: 3)
    private let keys: [Key] = (1...9).map(Key.digit) + [.delete, .digit(0), .unlock]

    var body: some View {
        VStack(spacing: 18) {
            Text(displayText)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PlinxBrand.shell)
                .frame(width: 478, height: 68)
                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(text.isEmpty ? "Empty" : text)
                .accessibilityIdentifier("parentalGate.numberEntry")

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(keys, id: \.self) { key in
                    keyButton(key)
                }
            }
        }
        .onAppear {
            focusedKey = .digit(1)
        }
    }

    private var displayText: String {
        guard !text.isEmpty else { return "—" }
        return isSecure ? String(repeating: "●", count: text.count) : text
    }

    private func keyButton(_ key: Key) -> some View {
        Button {
            activate(key)
        } label: {
            Group {
                switch key {
                case let .digit(value):
                    Text(String(value))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                case .delete:
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 28, weight: .semibold))
                case .unlock:
                    Text("parental.gate.unlock", tableName: "Plinx")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: 150, height: 70)
        }
        .buttonStyle(TvParentalKeyStyle(isUnlock: key == .unlock))
        .focused($focusedKey, equals: key)
        .accessibilityIdentifier(accessibilityIdentifier(for: key))
        .accessibilityValue(
            key == .unlock ? PlinxBrandingSemantics.parentalGateUnlockStyleValue : ""
        )
    }

    private func activate(_ key: Key) {
        switch key {
        case let .digit(value):
            guard text.count < maximumDigits else { return }
            text.append(String(value))
        case .delete:
            guard !text.isEmpty else { return }
            text.removeLast()
        case .unlock:
            onSubmit()
        }
    }

    private func accessibilityIdentifier(for key: Key) -> String {
        switch key {
        case let .digit(value):
            return "parentalGate.key.\(value)"
        case .delete:
            return "parentalGate.delete"
        case .unlock:
            return "parentalGate.unlock"
        }
    }
}

private struct TvParentalKeyStyle: ButtonStyle {
    let isUnlock: Bool

    func makeBody(configuration: Configuration) -> some View {
        TvParentalKeyBody(configuration: configuration, isUnlock: isUnlock)
    }
}

private struct TvParentalKeyBody: View {
    let configuration: TvParentalKeyStyle.Configuration
    let isUnlock: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(isUnlock ? Color.white : PlinxBrand.shell)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUnlock ? Color.accentColor : Color.white.opacity(isFocused ? 0.98 : 0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isFocused ? PlinxBrand.shell : Color.clear, lineWidth: 4)
            )
            .shadow(color: isFocused ? PlinxBrand.shell.opacity(0.32) : .clear, radius: 14)
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}
#endif

private struct NumberPadEntryField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = false
    var maximumDigits: Int? = nil
    var accessibilityLabel: String
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, maximumDigits: maximumDigits, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.keyboardAppearance = .light
        textField.returnKeyType = .done
        textField.enablesReturnKeyAutomatically = false
        textField.font = .preferredFont(forTextStyle: .title2)
        textField.adjustsFontForContentSizeCategory = true
        textField.textAlignment = .center
        textField.placeholder = placeholder
        textField.isSecureTextEntry = isSecure
        textField.accessibilityLabel = accessibilityLabel
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        #if !os(tvOS)
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem.flexibleSpace(),
            UIBarButtonItem(
                title: NSLocalizedString("common.actions.done", tableName: "Plinx", comment: ""),
                style: .done,
                target: context.coordinator,
                action: #selector(Coordinator.submit)
            )
        ]
        textField.inputAccessoryView = toolbar
        #endif
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.isSecureTextEntry = isSecure
        uiView.accessibilityLabel = accessibilityLabel
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let maximumDigits: Int?
        private let onSubmit: () -> Void

        init(text: Binding<String>, maximumDigits: Int?, onSubmit: @escaping () -> Void) {
            _text = text
            self.maximumDigits = maximumDigits
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ sender: UITextField) {
            let filtered = filteredText(from: sender.text ?? "")
            if sender.text != filtered {
                sender.text = filtered
            }
            text = filtered
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let stringRange = Range(range, in: current) else { return false }
            let updated = current.replacingCharacters(in: stringRange, with: string)
            let filtered = filteredText(from: updated)

            if filtered != updated {
                textField.text = filtered
                text = filtered
                return false
            }

            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            submit()
            return false
        }

        @objc func submit() {
            onSubmit()
        }

        private func filteredText(from source: String) -> String {
            let digitsOnly = source.filter { $0.isNumber }
            guard let maximumDigits else { return digitsOnly }
            return String(digitsOnly.prefix(maximumDigits))
        }
    }
}

import SwiftUI
import UIKit
import PlinxCore
import PlinxUI

struct ParentalGateView: View {
    @Environment(\.plinxTheme) private var theme
    @AppStorage("plinx.parentalPin") private var storedPin = ""

    // Math gate state
    @State private var challenge: MathGate.Challenge
    @State private var answerText = ""
    private var mathGate = MathGate()

    // PIN gate state
    @State private var pinEntry = ""
    @State private var pinError = false

    var onAllowed: () -> Void

    init(onAllowed: @escaping () -> Void) {
        var rng = SystemRandomNumberGenerator()
        _challenge = State(initialValue: mathGate.makeChallenge(rng: &rng))
        self.onAllowed = onAllowed
    }

    private var usePIN: Bool { !storedPin.isEmpty }

    var body: some View {
        VStack(spacing: 24) {
            PlinxBrandedLoadingView(
                preferredLogoAssetName: "LogoStackedFullWhite",
                logoAccessibilityIdentifier: "parentalGate.logo",
                showsProgressView: false
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
            LinearGradient.plinxBrandGreen.ignoresSafeArea()
        }
    }

    // MARK: - PIN gate

    private var pinChallengeView: some View {
        VStack(spacing: 20) {
            Text("parental.gate.pin.title", tableName: "Plinx")
                .font(.title2.bold())
                .foregroundStyle(theme.palette.background)
                .accessibilityIdentifier("parentalGate.title")

            NumberPadEntryField(
                text: $pinEntry,
                placeholder: "",
                isSecure: true,
                maximumDigits: 6
            )
                .frame(maxWidth: 200)
                .onChange(of: pinEntry) { _, _ in
                    pinError = false
                }

            if pinError {
                Text("parental.gate.pin.wrong", tableName: "Plinx")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            LiquidGlassButton(LocalizedStringResource("parental.gate.unlock", table: "Plinx")) {
                if pinEntry == storedPin {
                    onAllowed()
                } else {
                    pinError = true
                    pinEntry = ""
                }
            }
        }
    }

    // MARK: - Math gate

    private var mathChallengeView: some View {
        VStack(spacing: 20) {
            Text("parental.gate.title", tableName: "Plinx")
                .font(.title2.bold())
                .foregroundStyle(theme.palette.background)
                .accessibilityIdentifier("parentalGate.title")
                .accessibilityValue(PlinxBrandingSemantics.parentalGateTitleColorValue)

            Text(challenge.prompt)
                .font(.system(size: 48, weight: .black, design: .rounded))

            NumberPadEntryField(
                text: $answerText,
                placeholder: NSLocalizedString("parental.gate.placeholder", tableName: "Plinx", comment: "")
            )
                .frame(maxWidth: 200)

            LiquidGlassButton(LocalizedStringResource("parental.gate.unlock", table: "Plinx")) {
                if let answer = Int(answerText), mathGate.validate(answer: answer, for: challenge) {
                    onAllowed()
                } else {
                    var rng = SystemRandomNumberGenerator()
                    challenge = mathGate.makeChallenge(rng: &rng)
                    answerText = ""
                }
            }
        }
    }
}

private struct NumberPadEntryField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = false
    var maximumDigits: Int? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, maximumDigits: maximumDigits)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.keyboardAppearance = .light
        textField.textColor = .black
        textField.tintColor = .black
        textField.textAlignment = .center
        textField.font = .preferredFont(forTextStyle: .largeTitle)
        textField.adjustsFontForContentSizeCategory = true
        textField.placeholder = placeholder
        textField.isSecureTextEntry = isSecure
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.isSecureTextEntry = isSecure
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let maximumDigits: Int?

        init(text: Binding<String>, maximumDigits: Int?) {
            _text = text
            self.maximumDigits = maximumDigits
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

        private func filteredText(from source: String) -> String {
            let digitsOnly = source.filter { $0.isNumber }
            guard let maximumDigits else { return digitsOnly }
            return String(digitsOnly.prefix(maximumDigits))
        }
    }
}

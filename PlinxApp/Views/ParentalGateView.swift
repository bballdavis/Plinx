import SwiftUI
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

            SecureField("", text: $pinEntry)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.largeTitle)
                .frame(maxWidth: 200)
                .onChange(of: pinEntry) { _, val in
                    let digits = val.filter { $0.isNumber }
                    pinEntry = String(digits.prefix(6))
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

            TextField(text: $answerText) {
                Text("parental.gate.placeholder", tableName: "Plinx")
            }
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.largeTitle)
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

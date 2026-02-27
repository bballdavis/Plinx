import SwiftUI
import PlinxCore
import PlinxUI

struct ParentalGateView: View {
    @Environment(\.plinxTheme) private var theme

    @State private var challenge: MathGate.Challenge
    @State private var answerText = ""
    private var mathGate = MathGate()
    var onAllowed: () -> Void

    init(onAllowed: @escaping () -> Void) {
        var rng = SystemRandomNumberGenerator()
        _challenge = State(initialValue: mathGate.makeChallenge(rng: &rng))
        self.onAllowed = onAllowed
    }

    var body: some View {
        VStack(spacing: 24) {
            PlinxBrandedLoadingView(
                preferredLogoAssetName: "LogoFullColor",
                logoAccessibilityIdentifier: "parentalGate.logo",
                showsProgressView: false
            )
                .frame(height: 200)

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
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient.plinxBrandGreen.ignoresSafeArea()
        }
    }
}

import SwiftUI
import PlinxCore
import PlinxUI

struct ParentalGateView: View {
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
            PlinxieLoadingView()
                .frame(height: 200)

            Text("Parents Only")
                .font(.title2.bold())
                .foregroundStyle(PlinxTheme().primaryColor)

            Text(challenge.prompt)
                .font(.system(size: 48, weight: .black, design: .rounded))

            TextField("Answer", text: $answerText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.largeTitle)
                .frame(maxWidth: 200)

            LiquidGlassButton("Unlock") {
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
    }
}

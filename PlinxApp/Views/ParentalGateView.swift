import SwiftUI
import PlinxCore
import PlinxUI

struct ParentalGateView: View {
    @State private var challenge: MathGate.Challenge
    @State private var answerText = ""
    @State private var isUnlocked = false
    private var mathGate = MathGate()

    init() {
        var rng = SystemRandomNumberGenerator()
        _challenge = State(initialValue: mathGate.makeChallenge(rng: &rng))
    }

    var body: some View {
        VStack(spacing: 16) {
            PlinxieLoadingView()

            Text("Parents Only")
                .font(.title2.bold())

            Text(challenge.prompt)
                .font(.title)

            TextField("Answer", text: $answerText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(maxWidth: 160)

            LiquidGlassButton("Unlock") {
                if let answer = Int(answerText), mathGate.validate(answer: answer, for: challenge) {
                    isUnlocked = true
                } else {
                    var rng = SystemRandomNumberGenerator()
                    challenge = mathGate.makeChallenge(rng: &rng)
                    answerText = ""
                }
            }

            if isUnlocked {
                Text("Unlocked")
                    .font(.headline)
            }
        }
        .padding()
    }
}

import SwiftUI
import PlinxUI

/// Lets the parent set (or clear) a 4-6 digit numeric PIN that will replace
/// the math-equation gate when the settings are opened.
struct SetPinView: View {
    @AppStorage("plinx.parentalPin") private var storedPin = ""
    @Environment(\.plinxTheme) private var theme

    private enum Step { case enter, confirm }

    @State private var step: Step = .enter
    @State private var firstEntry = ""
    @State private var secondEntry = ""
    @State private var entryError = false

    var body: some View {
        List {
            if !storedPin.isEmpty {
                // MARK: Current PIN status
                Section {
                    Label("PIN is set", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Button(role: .destructive) {
                        storedPin = ""
                        firstEntry = ""
                        secondEntry = ""
                        step = .enter
                        entryError = false
                    } label: {
                        Label("Remove PIN (use math gate)", systemImage: "xmark.shield")
                    }
                } header: {
                    Text("Current PIN")
                }
            }

            // MARK: Set new PIN
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(step == .enter ? "Enter new PIN" : "Confirm new PIN")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        SecureField("4-6 digits", text: step == .enter ? $firstEntry : $secondEntry)
                            .keyboardType(.numberPad)
                            .font(.title2.monospacedDigit())
                            .onChange(of: step == .enter ? firstEntry : secondEntry) { _, newVal in
                                entryError = false
                                // Limit to 6 digits
                                let digits = newVal.filter { $0.isNumber }
                                if step == .enter {
                                    firstEntry = String(digits.prefix(6))
                                } else {
                                    secondEntry = String(digits.prefix(6))
                                }
                            }
                    }

                    if entryError {
                        Text(step == .enter ? "PIN must be 4-6 digits" : "PINs do not match. Try again.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        handleNext()
                    } label: {
                        Text(step == .enter ? "Next" : "Save PIN")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled((step == .enter ? firstEntry : secondEntry).count < 4)
                }
                .padding(.vertical, 4)
            } header: {
                Text(storedPin.isEmpty ? "Set a PIN" : "Change PIN")
            } footer: {
                Text("Enter 4-6 digits. This PIN will replace the math challenge when unlocking settings.")
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Set PIN")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handleNext() {
        switch step {
        case .enter:
            guard firstEntry.count >= 4 else {
                entryError = true
                return
            }
            step = .confirm
            secondEntry = ""
            entryError = false
        case .confirm:
            if secondEntry == firstEntry {
                storedPin = firstEntry
                firstEntry = ""
                secondEntry = ""
                step = .enter
                entryError = false
            } else {
                entryError = true
                secondEntry = ""
            }
        }
    }
}

import SwiftUI
import PlinxUI

/// Lets the parent set (or clear) a 4-6 digit numeric PIN that will replace
/// the math-equation gate when the settings are opened.
struct SetPinView: View {
    @Environment(ParentalAccessCoordinator.self) private var parentalAccessCoordinator
    @Environment(\.plinxTheme) private var theme

    private enum Step { case verifyCurrent, enter, confirm }

    @State private var step: Step = .enter
    @State private var currentEntry = ""
    @State private var firstEntry = ""
    @State private var secondEntry = ""
    @State private var entryError = false

    var body: some View {
        List {
            if parentalAccessCoordinator.hasPIN {
                // MARK: Current PIN status
                Section {
                    Label {
                        Text("settings.parentalPIN.isSet", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "checkmark.shield.fill")
                    }
                        .foregroundStyle(.green)
                    Button(role: .destructive) {
                        removePIN()
                    } label: {
                        Label {
                            Text("settings.parentalPIN.remove", tableName: "Plinx")
                        } icon: {
                            Image(systemName: "xmark.shield")
                        }
                    }
                } header: {
                    Text("settings.parentalPIN.current", tableName: "Plinx")
                }
            }

            // MARK: Set new PIN
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(stepTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        SecureField(
                            String(localized: "settings.parentalPIN.digits", table: "Plinx"),
                            text: activeEntryBinding
                        )
                            .keyboardType(.numberPad)
                            .font(.title2.monospacedDigit())
                            .onChange(of: activeEntryValue) { _, newVal in
                                entryError = false
                                // Limit to 6 digits
                                let digits = newVal.filter { $0.isNumber }
                                if step == .verifyCurrent {
                                    currentEntry = String(digits.prefix(6))
                                } else if step == .enter {
                                    firstEntry = String(digits.prefix(6))
                                } else {
                                    secondEntry = String(digits.prefix(6))
                                }
                            }
                    }

                    if entryError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        handleNext()
                    } label: {
                        Text(
                            step == .confirm
                                ? String(localized: "settings.parentalPIN.save", table: "Plinx")
                                : String(localized: "common.actions.next", table: "Plinx")
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(activeEntryValue.count < 4)
                }
                .padding(.vertical, 4)
            } header: {
                Text(
                    parentalAccessCoordinator.hasPIN
                        ? String(localized: "settings.parentalPIN.change", table: "Plinx")
                        : String(localized: "settings.parentalPIN.set", table: "Plinx")
                )
            } footer: {
                Text("settings.parentalPIN.footer", tableName: "Plinx")
                    .font(.caption)
            }
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(Text("settings.parentalPIN.navigationTitle", tableName: "Plinx"))
        .onAppear {
            step = parentalAccessCoordinator.hasPIN ? .verifyCurrent : .enter
        }
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func handleNext() {
        switch step {
        case .verifyCurrent:
            guard currentEntry.count >= 4 else {
                entryError = true
                return
            }
            step = .enter
            firstEntry = ""
            entryError = false
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
                let result = parentalAccessCoordinator.setPIN(
                    firstEntry,
                    currentPIN: parentalAccessCoordinator.hasPIN ? currentEntry : nil
                )
                guard result == .success else {
                    entryError = true
                    secondEntry = ""
                    return
                }
                firstEntry = ""
                secondEntry = ""
                currentEntry = ""
                step = .verifyCurrent
                entryError = false
            } else {
                entryError = true
                secondEntry = ""
            }
        }
    }

    private var activeEntryBinding: Binding<String> {
        switch step {
        case .verifyCurrent:
            return $currentEntry
        case .enter:
            return $firstEntry
        case .confirm:
            return $secondEntry
        }
    }

    private var activeEntryValue: String {
        switch step {
        case .verifyCurrent:
            return currentEntry
        case .enter:
            return firstEntry
        case .confirm:
            return secondEntry
        }
    }

    private var stepTitle: String {
        switch step {
        case .verifyCurrent:
            return String(localized: "settings.parentalPIN.enterCurrent", table: "Plinx")
        case .enter:
            return String(localized: "settings.parentalPIN.enterNew", table: "Plinx")
        case .confirm:
            return String(localized: "settings.parentalPIN.confirmNew", table: "Plinx")
        }
    }

    private var errorMessage: String {
        switch step {
        case .verifyCurrent:
            return String(localized: "settings.parentalPIN.error.currentRequired", table: "Plinx")
        case .enter:
            return String(localized: "settings.parentalPIN.error.invalidFormat", table: "Plinx")
        case .confirm:
            return String(localized: "settings.parentalPIN.error.mismatch", table: "Plinx")
        }
    }

    private func removePIN() {
        guard currentEntry.count >= 4 else {
            step = .verifyCurrent
            entryError = true
            return
        }
        if parentalAccessCoordinator.removePIN(currentPIN: currentEntry) == .success {
            currentEntry = ""
            firstEntry = ""
            secondEntry = ""
            step = .enter
            entryError = false
        } else {
            step = .verifyCurrent
            currentEntry = ""
            entryError = true
        }
    }
}

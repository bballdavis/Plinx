import SwiftUI

struct PlayerView: View {
    @State private var isLocked = false
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showControls {
                VStack {
                    HStack {
                        Button("X") {}
                            .font(.title.bold())
                        Spacer()
                        Toggle("Lock", isOn: $isLocked)
                            .labelsHidden()
                    }
                    .padding()

                    Spacer()

                    Button {
                        showControls.toggle()
                    } label: {
                        Image(systemName: "playpause.fill")
                            .font(.system(size: 56))
                            .padding()
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    Text("Scrub Bar")
                        .foregroundStyle(.white)
                        .padding()
                }
                .foregroundStyle(.white)
            }
        }
        .disabled(isLocked)
        .onTapGesture(count: 3) {
            if isLocked {
                isLocked = false
            }
        }
    }
}

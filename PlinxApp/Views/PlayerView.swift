import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isLocked = false
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !isLocked && showControls {
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                        }
                        
                        Spacer()
                        
                        Button {
                            isLocked = true
                        } label: {
                            Image(systemName: "lock.open.fill")
                                .font(.title)
                        }
                    }
                    .padding()

                    Spacer()

                    Button {
                        // Play/Pause logic would go here
                    } label: {
                        Image(systemName: "playpause.fill")
                            .font(.system(size: 56))
                            .padding()
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    Text("Triple tap to unlock")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding()
                }
                .foregroundStyle(.white)
            }
            
            if isLocked {
                // Invisible overlay to catch taps if locked? 
                // Actually theCounted tap gesture below handles it.
                Color.black.opacity(0.001)
            }
        }
        .onTapGesture(count: 3) {
            if isLocked {
                isLocked = false
                showControls = true
            }
        }
        .onTapGesture {
            if !isLocked {
                showControls.toggle()
            }
        }
    }
}

import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        VStack(spacing: 16) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Text("Results")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 20)
    }
}

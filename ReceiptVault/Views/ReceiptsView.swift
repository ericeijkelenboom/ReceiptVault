import SwiftUI

struct ReceiptsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("No receipts yet.")
                    .font(.headline)
                Text("Share a photo from Photos to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Receipts")
        }
    }
}

#Preview {
    ReceiptsView()
}

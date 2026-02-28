import SwiftUI

struct ProcessingQueueView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "tray")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("No pending items.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Queue")
        }
    }
}

#Preview {
    ProcessingQueueView()
}

import SwiftUI

struct ProcessingQueueView: View {
    @EnvironmentObject private var processingController: ProcessingController

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: processingController.isProcessing ? "tray.and.arrow.down.fill" : "tray")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text(processingController.isProcessing ? "Processing items..." : "No pending items.")
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
        .environmentObject(ProcessingController())
}

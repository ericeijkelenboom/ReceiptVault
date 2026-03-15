import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var processingController: ProcessingController

    var body: some View {
        ReceiptsView()
            .alert("Error", isPresented: .constant(processingController.lastError != nil)) {
                Button("OK") {
                    processingController.clearError()
                }
            } message: {
                if let error = processingController.lastError {
                    Text(error.errorDescription ?? "Unknown error")
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProcessingController())
        .environmentObject(ReceiptStoreCore())
}

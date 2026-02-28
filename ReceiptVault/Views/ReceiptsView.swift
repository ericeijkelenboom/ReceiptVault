import SwiftUI
import PhotosUI

struct ReceiptsView: View {
    @EnvironmentObject private var processingController: ProcessingController
    @State private var selectedItem: PhotosPickerItem?

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

                if processingController.isProcessing {
                    ProgressView("Processing receipt…")
                        .padding(.top)
                }

                if let message = processingController.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Receipts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images
                    ) {
                        Image(systemName: "plus")
                    }
                    .disabled(processingController.isProcessing)
                }
            }
        }
        .onChange(of: selectedItem) { newItem in
            guard let newItem else { return }
            Task {
                defer { Task { @MainActor in selectedItem = nil } }
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await processingController.process(image: image)
                    }
                }
            }
        }
    }
}

#Preview {
    ReceiptsView()
        .environmentObject(ProcessingController())
}


import SwiftUI
import PhotosUI

struct ReceiptsView: View {
    @EnvironmentObject private var processingController: ProcessingController
    @EnvironmentObject private var receiptStore: ReceiptStore
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedItem: PhotosPickerItem?
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            Group {
                if receiptStore.receipts.isEmpty {
                    emptyState
                } else {
                    receiptList
                }
            }
            .navigationTitle("Receipts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
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
                } catch {
                    await MainActor.run { processingController.lastErrorMessage = error.localizedDescription }
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No receipts yet.")
                .font(.headline)
            Text("Tap + to add a receipt from your photo library.")
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
    }

    private var receiptList: some View {
        List {
            if processingController.isProcessing {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Processing receipt…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let message = processingController.lastErrorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            ForEach(receiptStore.groupedByMonth, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.receipts) { receipt in
                        ReceiptRow(receipt: receipt)
                    }
                }
            }
        }
        .refreshable {
            isSyncing = true
            defer { isSyncing = false }
            try? await receiptStore.syncFromDrive(authManager: authManager)
        }
    }
}

// MARK: - Receipt Row

private struct ReceiptRow: View {
    let receipt: CachedReceipt

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.shopName)
                    .font(.headline)
                Text(receipt.date, format: .dateTime.day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let total = receipt.total, let currency = receipt.currency {
                Text(total as NSDecimalNumber as Decimal, format: .currency(code: currency))
                    .font(.headline)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ReceiptsView()
        .environmentObject(ProcessingController())
        .environmentObject(ReceiptStore())
        .environmentObject(AuthManager())
}

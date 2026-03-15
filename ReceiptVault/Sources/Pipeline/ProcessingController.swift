import SwiftUI
import UIKit

@MainActor
final class ProcessingController: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var totalInBatch = 0
    @Published private(set) var processingStep: String?
    @Published var lastError: ReceiptVaultError?

    var pipeline: ProcessingPipeline?
    private var queue: [UIImage] = []

    let quotaManager = QuotaManager()
    let receiptStore = ReceiptStoreCore()

    // Clears the last error state.
    func clearError() {
        lastError = nil
    }

    // Process a receipt and save to Core Data with quota checking
    func processReceipt(_ receiptData: ReceiptData, jpgPath: String) async {
        isProcessing = true
        defer { isProcessing = false }
        clearError()

        // Check quota
        guard quotaManager.canAddReceipt() else {
            lastError = .parseFailure("Free tier limit reached. Upgrade to add more receipts.")
            return
        }

        do {
            // Save to Core Data
            try await receiptStore.saveReceipt(data: receiptData, jpgPath: jpgPath)

            // Record quota usage
            quotaManager.recordReceiptAdded()

            print("[ProcessingController] Receipt saved to Core Data and quota recorded.")
        } catch let error as ReceiptVaultError {
            lastError = error
        } catch {
            lastError = .parseFailure("Failed to save receipt: \(error.localizedDescription)")
        }
    }

    // Enqueues `image` for processing. If nothing is currently running,
    // kicks off the processing loop immediately.
    func process(image: UIImage) {
        queue.append(image)
        pendingCount = queue.count
        if isProcessing {
            totalInBatch += 1  // extend the running batch
        }
        guard !isProcessing else { return }
        Task { await processQueue() }
    }

    func drainQueue() async {
        guard let pipeline else {
            lastError = .parseFailure("Processing pipeline not configured")
            return
        }
        guard !isProcessing else {
            print("[ProcessingController] Ignoring drainQueue() while another operation is in progress.")
            return
        }

        isProcessing = true
        clearError()
        defer { isProcessing = false }

        print("[ProcessingController] Starting drainQueue() from App Group jobs…")
        do {
            try await pipeline.drainQueue()
            print("[ProcessingController] drainQueue() completed.")
        } catch let error as ReceiptVaultError {
            lastError = error
        } catch {
            lastError = .parseFailure("Failed to process queued receipts: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func processQueue() async {
        guard let pipeline else {
            print("[ProcessingController] No pipeline configured; cannot process queue.")
            queue.removeAll()
            pendingCount = 0
            return
        }

        isProcessing = true
        clearError()
        totalInBatch = queue.count
        defer {
            isProcessing = false
            processingStep = nil
            totalInBatch = 0
        }

        while !queue.isEmpty {
            let image = queue.removeFirst()
            pendingCount = queue.count
            print("[ProcessingController] Processing image; \(pendingCount) remaining in queue.")
            do {
                try await pipeline.process(image: image) { [weak self] step in
                    self?.processingStep = step
                }
                print("[ProcessingController] Image processed successfully.")
            } catch let error as ReceiptVaultError {
                print("[ProcessingController] Processing failed: \(error)")
                lastError = error
            } catch {
                print("[ProcessingController] Processing failed: \(error)")
                lastError = .parseFailure("An unexpected error occurred: \(error.localizedDescription)")
            }
        }
    }
}

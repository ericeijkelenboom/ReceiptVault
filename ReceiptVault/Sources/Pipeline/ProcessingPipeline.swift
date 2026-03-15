import UIKit
import UserNotifications

@MainActor
final class ProcessingPipeline {
    private let receiptStore: ReceiptStoreCore
    private let appGroupIdentifier = "group.com.ericeijkelenboom.receiptvault"
    private let pendingJobsKey = "pendingReceiptJobs"

    private var isProcessing = false

    private let receiptParser: ReceiptParser
    private let pdfBuilder = PDFBuilder()

    init(receiptStore: ReceiptStoreCore) {
        self.receiptStore = receiptStore
        self.receiptParser = ReceiptParser()
    }

    // MARK: - Public

    func drainQueue() async throws {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw ReceiptVaultError.parseFailure("Cannot access App Group storage")
        }
        let jobs = defaults.stringArray(forKey: pendingJobsKey) ?? []
        guard !jobs.isEmpty else { return }

        var processed: Set<String> = []
        var lastError: Error?

        for filename in jobs {
            do {
                print("[ProcessingPipeline] Processing queued file: \(filename)")
                let image = try loadImage(filename: filename)
                try await runPipeline(for: image, onStep: { _ in })
                print("[ProcessingPipeline] Finished queued file: \(filename)")
            } catch {
                print("[ProcessingPipeline] Error processing queued file \(filename): \(error)")
                lastError = error
                await notify(
                    title: "Receipt failed",
                    body: error.localizedDescription
                )
            }

            // Remove from queue regardless of success/failure to avoid infinite retries
            processed.insert(filename)
            let remaining = jobs.filter { !processed.contains($0) }
            defaults.set(remaining, forKey: pendingJobsKey)
            deleteFile(filename: filename)
        }

        // If any file failed, throw the last error so it appears in the UI
        if let lastError = lastError as? ReceiptVaultError {
            throw lastError
        } else if let lastError = lastError {
            throw ReceiptVaultError.parseFailure("Failed to process receipt: \(lastError.localizedDescription)")
        }
    }

    func process(image: UIImage, onStep: (String) -> Void = { _ in }) async throws {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            print("[ProcessingPipeline] Starting in-app pipeline for image…")
            try await runPipeline(for: image, onStep: onStep)
            print("[ProcessingPipeline] In-app pipeline completed successfully.")
        } catch {
            print("[ProcessingPipeline] In-app pipeline failed with error: \(error)")
            await notify(
                title: "Receipt failed",
                body: error.localizedDescription
            )
            throw error
        }
    }

    // MARK: - Shared pipeline

    private func runPipeline(for image: UIImage, onStep: (String) -> Void) async throws {
        onStep("Reading receipt…")
        print("[ProcessingPipeline] Step 1/3 – calling ReceiptParser.parse(image:)")
        let receiptData = try await receiptParser.parse(image: image)
        print("[ProcessingPipeline] Step 1/3 complete – parsed receipt for shop: \(receiptData.shopName)")

        onStep("Building PDF…")
        print("[ProcessingPipeline] Step 2/3 – building PDF")
        let pdfData = try await pdfBuilder.build(image: image, receiptData: receiptData)
        print("[ProcessingPipeline] Step 2/3 complete – PDF built (\(pdfData.count) bytes)")

        onStep("Saving receipt…")
        print("[ProcessingPipeline] Step 3/3 – saving to local storage with iCloud sync")
        // Save to Core Data with iCloud CloudKit sync
        // TODO: Store pdfData alongside receipt in Core Data
        try await receiptStore.saveReceipt(data: receiptData, jpgPath: "")
        print("[ProcessingPipeline] Step 3/3 complete")

        await notify(
            title: "Receipt saved ✓",
            body: "Receipt from \(receiptData.shopName) saved and syncing via iCloud."
        )
    }

    // MARK: - App Group I/O

    private func loadImage(filename: String) throws -> UIImage {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ReceiptVaultError.parseFailure("App Group container not available")
        }
        let fileURL = containerURL.appendingPathComponent("PendingReceipts/\(filename)")
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            throw ReceiptVaultError.parseFailure("Could not load image: \(filename)")
        }
        return image
    }

    private func deleteFile(filename: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return }
        let fileURL = containerURL.appendingPathComponent("PendingReceipts/\(filename)")
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Notifications

    private func notify(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}


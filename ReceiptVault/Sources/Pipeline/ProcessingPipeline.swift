import UIKit
import UserNotifications

@MainActor
final class ProcessingPipeline {
    private let authManager: AuthManager
    private let appGroupIdentifier = "group.com.ericeijkelenboom.receiptvault"
    private let pendingJobsKey = "pendingReceiptJobs"

    private var isProcessing = false

    private let receiptParser = ReceiptParser()
    private let pdfBuilder = PDFBuilder()
    private lazy var driveUploader = DriveUploader(authManager: authManager)

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - Public

    func drainQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let jobs = defaults.stringArray(forKey: pendingJobsKey) ?? []
        guard !jobs.isEmpty else { return }

        var processed: Set<String> = []

        for filename in jobs {
            do {
                let image = try loadImage(filename: filename)
                let receiptData = try await receiptParser.parse(image: image)
                let pdfData = try await pdfBuilder.build(image: image, receiptData: receiptData)
                _ = try await driveUploader.upload(pdf: pdfData, receiptData: receiptData)

                await notify(
                    title: "Receipt saved ✓",
                    body: "Receipt from \(receiptData.shopName) saved to Google Drive."
                )
            } catch {
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

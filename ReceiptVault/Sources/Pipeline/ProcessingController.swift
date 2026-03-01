import SwiftUI
import UIKit

@MainActor
final class ProcessingController: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var pendingCount = 0
    @Published var lastErrorMessage: String?

    var pipeline: ProcessingPipeline?
    private var queue: [UIImage] = []

    // Enqueues `image` for processing. If nothing is currently running,
    // kicks off the processing loop immediately.
    func process(image: UIImage) {
        queue.append(image)
        pendingCount = queue.count
        guard !isProcessing else { return }
        Task { await processQueue() }
    }

    func drainQueue() async {
        guard let pipeline else {
            print("[ProcessingController] No pipeline configured; cannot drain queue.")
            return
        }
        guard !isProcessing else {
            print("[ProcessingController] Ignoring drainQueue() while another operation is in progress.")
            return
        }

        isProcessing = true
        lastErrorMessage = nil
        defer { isProcessing = false }

        print("[ProcessingController] Starting drainQueue() from App Group jobs…")
        await pipeline.drainQueue()
        print("[ProcessingController] drainQueue() completed.")
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
        lastErrorMessage = nil

        while !queue.isEmpty {
            let image = queue.removeFirst()
            pendingCount = queue.count
            print("[ProcessingController] Processing image; \(pendingCount) remaining in queue.")
            do {
                try await pipeline.process(image: image)
                print("[ProcessingController] Image processed successfully.")
            } catch {
                print("[ProcessingController] Processing failed: \(error)")
                lastErrorMessage = error.localizedDescription
            }
        }

        isProcessing = false
    }
}

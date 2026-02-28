import SwiftUI
import UIKit

@MainActor
final class ProcessingController: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published var lastErrorMessage: String?

    var pipeline: ProcessingPipeline?

    func process(image: UIImage) async {
        guard let pipeline else {
            print("[ProcessingController] No pipeline configured; cannot process image.")
            return
        }
        guard !isProcessing else {
            print("[ProcessingController] Ignoring process(image:) while another operation is in progress.")
            return
        }

        isProcessing = true
        lastErrorMessage = nil
        defer { isProcessing = false }

        do {
            print("[ProcessingController] Starting in-app receipt processing…")
            try await pipeline.process(image: image)
            print("[ProcessingController] In-app receipt processing finished successfully.")
        } catch {
            print("[ProcessingController] Processing failed with error: \(error)")
            lastErrorMessage = error.localizedDescription
        }
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
}


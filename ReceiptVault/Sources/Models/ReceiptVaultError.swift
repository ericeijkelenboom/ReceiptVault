import Foundation

enum ReceiptVaultError: LocalizedError {
    case notImplemented
    case parseFailure(String)
    case uploadFailure(String)
    case authRequired
    case networkError(Error)
    case pdfGenerationFailed

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This feature has not been implemented yet."
        case .parseFailure(let message),
             .uploadFailure(let message):
            return message
        case .authRequired:
            return "Authentication required. Please sign in with Google and save your Claude API key in Settings."
        case .networkError(let underlying):
            return underlying.localizedDescription
        case .pdfGenerationFailed:
            return "Failed to generate the PDF for this receipt."
        }
    }
}


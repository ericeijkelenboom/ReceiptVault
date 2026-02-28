import Foundation

enum ReceiptVaultError: Error {
    case notImplemented
    case parseFailure(String)
    case uploadFailure(String)
    case authRequired
    case networkError(Error)
    case pdfGenerationFailed
}

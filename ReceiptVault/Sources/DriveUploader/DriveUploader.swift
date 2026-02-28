import Foundation

final class DriveUploader {
    /// Uploads a PDF to Google Drive and returns the Drive file ID.
    func upload(pdf: Data, receiptData: ReceiptData) async throws -> String {
        throw ReceiptVaultError.notImplemented
    }

    /// Creates a folder at the given path if it doesn't exist and returns the folder ID.
    func createFolderIfNeeded(path: String) async throws -> String {
        throw ReceiptVaultError.notImplemented
    }
}

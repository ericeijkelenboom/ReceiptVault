import Foundation

final class DriveUploader {
    private let authManager: AuthManager
    private let filesURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
    private let uploadURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files")!

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - Public

    /// Uploads a PDF to Google Drive, creates folder hierarchy if needed,
    /// updates manifest.json, and returns the Drive file ID.
    func upload(pdf: Data, receiptData: ReceiptData) async throws -> (fileId: String, filePath: String) {
        let calendar = Calendar(identifier: .gregorian)
        let yearInt = calendar.component(.year, from: receiptData.date)
        let currentYear = calendar.component(.year, from: Date())
        guard yearInt >= 1980, yearInt <= currentYear + 1 else {
            throw ReceiptVaultError.uploadFailure(
                "Receipt date year \(yearInt) is outside the expected range (1980–\(currentYear + 1))."
            )
        }
        let year = String(yearInt)
        let month = String(format: "%02d", calendar.component(.month, from: receiptData.date))
        let safeName = sanitizedFolderName(receiptData.shopName)
        let folderPath = "Receipts/\(safeName)/\(year)/\(month)"

        let monthFolderId = try await createFolderIfNeeded(path: folderPath)
        let filename = makeFilename(for: receiptData)
        let fileId = try await uploadFile(name: filename, data: pdf, mimeType: "application/pdf", parentId: monthFolderId)
        try await updateManifest(folderId: monthFolderId, receiptData: receiptData, filename: filename, driveFileId: fileId)
        return (fileId: fileId, filePath: "\(folderPath)/\(filename)")
    }

    /// Fetches full receipt details (including line items) for a given Drive file ID.
    /// Searches all manifest.json files on Drive to find the matching receipt.
    func fetchReceiptDetails(driveFileId: String) async throws -> ReceiptDetail? {
        let query = "name='manifest.json' and trashed=false"
        var components = URLComponents(url: filesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        let data = try await perform(try await authorizedRequest(url: components.url!, method: "GET"))
        struct FilesResponse: Decodable {
            struct File: Decodable { let id: String }
            let files: [File]
        }
        let filesList = try JSONDecoder().decode(FilesResponse.self, from: data).files

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        for file in filesList {
            guard let manifestData = try? await downloadFile(fileId: file.id) else { continue }
            if let detail = parseReceiptDetail(from: manifestData, driveFileId: driveFileId, dateFormatter: df) {
                return detail
            }
        }
        return nil
    }

    /// Updates the manifest entry for a receipt in-place on Drive.
    /// Preserves the PDF filename, folder, and line items — only metadata fields change.
    /// Returns the reconstructed driveFilePath (using original filename/folder) for Sheets sync.
    @discardableResult
    func updateManifestEntry(driveFileId: String, shopName: String, date: Date,
                             total: Decimal?, currency: String?) async throws -> String {
        // Get the PDF file's parent folder ID (same pattern as deleteReceipt)
        var metaComponents = URLComponents(url: filesURL.appendingPathComponent(driveFileId),
                                           resolvingAgainstBaseURL: false)!
        metaComponents.queryItems = [URLQueryItem(name: "fields", value: "parents")]
        let metaData = try await perform(try await authorizedRequest(url: metaComponents.url!, method: "GET"))
        struct FileMeta: Decodable { let parents: [String]? }
        guard let parentId = (try? JSONDecoder().decode(FileMeta.self, from: metaData))?.parents?.first else {
            throw ReceiptVaultError.uploadFailure("Could not find receipt folder on Drive")
        }

        guard let manifestId = try await findItem(name: "manifest.json", parentId: parentId) else { return "" }
        let existing = try await downloadFile(fileId: manifestId)
        var manifest = (try? JSONDecoder().decode(Manifest.self, from: existing)) ?? Manifest()

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let idx = manifest.receipts.firstIndex(where: { $0.driveFileId == driveFileId }) else { return "" }
        let old = manifest.receipts[idx]
        manifest.receipts[idx] = ManifestEntry(
            filename: old.filename,
            date: df.string(from: date),
            shopName: shopName,
            total: (total as NSDecimalNumber?)?.doubleValue,
            currency: currency,
            driveFileId: driveFileId,
            lineItems: old.lineItems
        )
        manifest.lastUpdated = ISO8601DateFormatter().string(from: Date())

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try await updateFileContent(fileId: manifestId, data: try encoder.encode(manifest),
                                    mimeType: "application/json")

        // Reconstruct the driveFilePath from the original entry (file was not moved/renamed)
        let calendar = Calendar(identifier: .gregorian)
        let originalDate = df.date(from: old.date) ?? date
        let year = String(calendar.component(.year, from: originalDate))
        let month = String(format: "%02d", calendar.component(.month, from: originalDate))
        let safeName = sanitizedFolderName(old.shopName)
        return "Receipts/\(safeName)/\(year)/\(month)/\(old.filename)"
    }

    /// Deletes the PDF for a receipt from Drive and removes it from the folder's manifest.json.
    func deleteReceipt(driveFileId: String) async throws {
        // Fetch the parent folder ID before deleting the file
        var metaComponents = URLComponents(url: filesURL.appendingPathComponent(driveFileId), resolvingAgainstBaseURL: false)!
        metaComponents.queryItems = [URLQueryItem(name: "fields", value: "parents")]
        let metaData = try await perform(try await authorizedRequest(url: metaComponents.url!, method: "GET"))
        struct FileMeta: Decodable { let parents: [String]? }
        let parentId = (try? JSONDecoder().decode(FileMeta.self, from: metaData))?.parents?.first

        // Delete the PDF file
        let deleteURL = filesURL.appendingPathComponent(driveFileId)
        _ = try await perform(try await authorizedRequest(url: deleteURL, method: "DELETE"))

        // Remove the entry from the parent folder's manifest.json
        if let parentId {
            try await removeFromManifest(driveFileId: driveFileId, folderId: parentId)
        }
    }

    /// Downloads a file from Drive by its file ID. Use for PDF receipt files.
    func downloadFile(fileId: String) async throws -> Data {
        var components = URLComponents(url: filesURL.appendingPathComponent(fileId), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        let request = try await authorizedRequest(url: components.url!, method: "GET")
        return try await perform(request)
    }

    /// Downloads all manifest.json files from Drive and returns their entries as CachedReceipts.
    func fetchAllReceipts() async throws -> [CachedReceipt] {
        let query = "name='manifest.json' and trashed=false"
        var components = URLComponents(url: filesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        let data = try await perform(try await authorizedRequest(url: components.url!, method: "GET"))
        struct FilesResponse: Decodable {
            struct File: Decodable { let id: String }
            let files: [File]
        }
        let filesList = try JSONDecoder().decode(FilesResponse.self, from: data).files

        var results: [CachedReceipt] = []
        for file in filesList {
            if let manifestData = try? await downloadFile(fileId: file.id) {
                results.append(contentsOf: parseCachedReceipts(from: manifestData))
            }
        }
        return results
    }

    /// Traverses (and creates) each component of a slash-separated folder path,
    /// starting from root, and returns the ID of the deepest folder.
    func createFolderIfNeeded(path: String) async throws -> String {
        let components = path.split(separator: "/").map(String.init)
        var parentId = "root"
        for component in components {
            parentId = try await findOrCreateFolder(name: component, parentId: parentId)
        }
        return parentId
    }

    // MARK: - Folder Operations

    private func findOrCreateFolder(name: String, parentId: String) async throws -> String {
        if let id = try await findItem(name: name, parentId: parentId, mimeType: "application/vnd.google-apps.folder") {
            return id
        }
        return try await createFolder(name: name, parentId: parentId)
    }

    private func createFolder(name: String, parentId: String) async throws -> String {
        let metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parentId]
        ]
        var request = try await authorizedRequest(url: filesURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let data = try await perform(request)
        struct Response: Decodable { let id: String }
        return try JSONDecoder().decode(Response.self, from: data).id
    }

    // MARK: - File Search

    private func findItem(name: String, parentId: String, mimeType: String? = nil) async throws -> String? {
        let escaped = name.replacingOccurrences(of: "'", with: "\\'")
        var query = "name='\(escaped)' and '\(parentId)' in parents and trashed=false"
        if let mimeType {
            query += " and mimeType='\(mimeType)'"
        }

        var components = URLComponents(url: filesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]

        let request = try await authorizedRequest(url: components.url!, method: "GET")
        let data = try await perform(request)

        struct Response: Decodable {
            struct File: Decodable { let id: String }
            let files: [File]
        }
        return try JSONDecoder().decode(Response.self, from: data).files.first?.id
    }

    // MARK: - File Upload / Download

    private func uploadFile(name: String, data: Data, mimeType: String, parentId: String) async throws -> String {
        let boundary = UUID().uuidString
        let metadata = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parentId]])

        var body = Data()
        body += "--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
        body += metadata
        body += "\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n"
        body += data
        body += "\r\n--\(boundary)--"

        var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]

        var request = try await authorizedRequest(url: components.url!, method: "POST")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let responseData = try await perform(request)
        struct Response: Decodable { let id: String }
        return try JSONDecoder().decode(Response.self, from: responseData).id
    }

    private func updateFileContent(fileId: String, data: Data, mimeType: String) async throws {
        var components = URLComponents(url: uploadURL.appendingPathComponent(fileId), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "media")]

        var request = try await authorizedRequest(url: components.url!, method: "PATCH")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try await perform(request)
    }

    // MARK: - Manifest

    private func updateManifest(folderId: String, receiptData: ReceiptData, filename: String, driveFileId: String) async throws {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        let entry = ManifestEntry(
            filename: filename,
            date: df.string(from: receiptData.date),
            shopName: receiptData.shopName,
            total: (receiptData.total as NSDecimalNumber?)?.doubleValue,
            currency: receiptData.currency,
            driveFileId: driveFileId,
            lineItems: receiptData.lineItems.map(ManifestLineItem.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        if let manifestId = try await findItem(name: "manifest.json", parentId: folderId) {
            let existing = try await downloadFile(fileId: manifestId)
            var manifest = (try? JSONDecoder().decode(Manifest.self, from: existing)) ?? Manifest()
            manifest.receipts.append(entry)
            manifest.lastUpdated = ISO8601DateFormatter().string(from: Date())
            try await updateFileContent(fileId: manifestId, data: try encoder.encode(manifest), mimeType: "application/json")
        } else {
            var manifest = Manifest()
            manifest.receipts = [entry]
            manifest.lastUpdated = ISO8601DateFormatter().string(from: Date())
            _ = try await uploadFile(name: "manifest.json", data: try encoder.encode(manifest), mimeType: "application/json", parentId: folderId)
        }
    }

    private func removeFromManifest(driveFileId: String, folderId: String) async throws {
        guard let manifestId = try await findItem(name: "manifest.json", parentId: folderId) else { return }
        let existing = try await downloadFile(fileId: manifestId)
        var manifest = (try? JSONDecoder().decode(Manifest.self, from: existing)) ?? Manifest()
        manifest.receipts.removeAll { $0.driveFileId == driveFileId }
        manifest.lastUpdated = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try await updateFileContent(fileId: manifestId, data: try encoder.encode(manifest), mimeType: "application/json")
    }

    // MARK: - Filename

    /// Returns a sanitised version of `name` safe to use as a Drive folder or file name component.
    /// - Replaces `/` and `\` with `-` so they don't split the folder path.
    /// - Strips ASCII control characters (< 0x20).
    /// - Trims surrounding whitespace.
    /// - Falls back to "Unknown" if the result is empty.
    private func sanitizedFolderName(_ name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .unicodeScalars
            .filter { $0.value >= 32 }
            .reduce(into: "") { $0.append(Character($1)) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Unknown" : cleaned
    }

    private func makeFilename(for receiptData: ReceiptData) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = df.string(from: receiptData.date)
        let safeName = sanitizedFolderName(receiptData.shopName)

        if let total = receiptData.total {
            let symbol = currencySymbol(for: receiptData.currency)
            return "\(dateStr)_\(safeName)_\(symbol)\(total).pdf"
        }
        return "\(dateStr)_\(safeName).pdf"
    }

    private func currencySymbol(for code: String?) -> String {
        switch code?.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case .none: return ""
        default: return "\(code!) "
        }
    }

    // MARK: - Manifest parsing for sync

    private func parseReceiptDetail(from data: Data, driveFileId: String, dateFormatter: DateFormatter) -> ReceiptDetail? {
        struct DTO: Decodable {
            struct Entry: Decodable {
                let filename: String
                let date: String
                let shopName: String
                let total: Double?
                let currency: String?
                let driveFileId: String
                let lineItems: [ManifestLineItem]
            }
            let receipts: [Entry]
        }
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data),
              let entry = dto.receipts.first(where: { $0.driveFileId == driveFileId }),
              let date = dateFormatter.date(from: entry.date) else { return nil }
        return ReceiptDetail(
            driveFileId: entry.driveFileId,
            filename: entry.filename,
            shopName: entry.shopName,
            date: date,
            total: entry.total.map { Decimal($0) },
            currency: entry.currency,
            lineItems: entry.lineItems.map { item in
                ReceiptDetailLineItem(
                    name: item.name,
                    quantity: item.quantity.map { Decimal($0) },
                    unitPrice: item.unitPrice.map { Decimal($0) },
                    totalPrice: item.totalPrice.map { Decimal($0) }
                )
            }
        )
    }

    private func parseCachedReceipts(from data: Data) -> [CachedReceipt] {
        struct DTO: Decodable {
            struct Entry: Decodable {
                let shopName: String
                let date: String
                let total: Double?
                let currency: String?
                let driveFileId: String
                let lineItems: [ManifestLineItem]?
            }
            let receipts: [Entry]
        }
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else { return [] }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return dto.receipts.compactMap { entry in
            guard let date = df.date(from: entry.date) else { return nil }
            let items = (entry.lineItems ?? []).map { item in
                LineItem(name: item.name,
                         quantity: item.quantity.map { Decimal($0) },
                         unitPrice: item.unitPrice.map { Decimal($0) },
                         totalPrice: item.totalPrice.map { Decimal($0) })
            }
            return CachedReceipt(
                driveFileId: entry.driveFileId,
                shopName: entry.shopName,
                date: date,
                total: entry.total.map { Decimal($0) },
                currency: entry.currency,
                scannedAt: date,
                lineItems: items
            )
        }
    }

    // MARK: - Networking

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        let token = try await authManager.freshAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ReceiptVaultError.uploadFailure("Drive API error \(status): \(body)")
        }
        return data
    }
}

// MARK: - Data helpers

private func += (lhs: inout Data, rhs: String) {
    if let d = rhs.data(using: .utf8) { lhs.append(d) }
}

private func += (lhs: inout Data, rhs: Data) {
    lhs.append(rhs)
}

// MARK: - Manifest models

private struct Manifest: Codable {
    var lastUpdated: String?
    var receipts: [ManifestEntry] = []
}

private struct ManifestEntry: Codable {
    let filename: String
    let date: String
    let shopName: String
    let total: Double?
    let currency: String?
    let driveFileId: String
    let lineItems: [ManifestLineItem]
}

private struct ManifestLineItem: Codable {
    let name: String
    let quantity: Double?
    let unitPrice: Double?
    let totalPrice: Double?

    init(_ item: LineItem) {
        name = item.name
        quantity = (item.quantity as NSDecimalNumber?)?.doubleValue
        unitPrice = (item.unitPrice as NSDecimalNumber?)?.doubleValue
        totalPrice = (item.totalPrice as NSDecimalNumber?)?.doubleValue
    }
}

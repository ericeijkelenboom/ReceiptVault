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
        let year = String(calendar.component(.year, from: receiptData.date))
        let month = String(format: "%02d", calendar.component(.month, from: receiptData.date))
        let folderPath = "Receipts/\(receiptData.shopName)/\(year)/\(month)"

        let monthFolderId = try await createFolderIfNeeded(path: folderPath)
        let filename = makeFilename(for: receiptData)
        let fileId = try await uploadFile(name: filename, data: pdf, mimeType: "application/pdf", parentId: monthFolderId)
        try await updateManifest(folderId: monthFolderId, receiptData: receiptData, filename: filename, driveFileId: fileId)
        return (fileId: fileId, filePath: "\(folderPath)/\(filename)")
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

    private func downloadFile(fileId: String) async throws -> Data {
        var components = URLComponents(url: filesURL.appendingPathComponent(fileId), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        let request = try await authorizedRequest(url: components.url!, method: "GET")
        return try await perform(request)
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

    // MARK: - Filename

    private func makeFilename(for receiptData: ReceiptData) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = df.string(from: receiptData.date)
        let safeName = receiptData.shopName.replacingOccurrences(of: "/", with: "-")

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

    private func parseCachedReceipts(from data: Data) -> [CachedReceipt] {
        struct DTO: Decodable {
            struct Entry: Decodable {
                let shopName: String
                let date: String
                let total: Double?
                let currency: String?
                let driveFileId: String
            }
            let receipts: [Entry]
        }
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else { return [] }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return dto.receipts.compactMap { entry in
            guard let date = df.date(from: entry.date) else { return nil }
            return CachedReceipt(
                driveFileId: entry.driveFileId,
                shopName: entry.shopName,
                date: date,
                total: entry.total.map { Decimal($0) },
                currency: entry.currency,
                scannedAt: date
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

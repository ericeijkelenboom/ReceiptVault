import Foundation

final class SheetsLogger {
    private let authManager: AuthManager
    private let sheetsBaseURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!
    private let driveFilesURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
    private let spreadsheetName = "ReceiptVault Index"

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - Public

    /// Appends a row to the central ReceiptVault Index Google Sheet,
    /// creating the sheet inside the Receipts folder if it doesn't exist yet.
    func log(receiptData: ReceiptData, driveFileId: String, driveFilePath: String) async throws {
        let spreadsheetId = try await findOrCreateSpreadsheet()
        try await appendRow(to: spreadsheetId, receiptData: receiptData, driveFileId: driveFileId, driveFilePath: driveFilePath)
    }

    // MARK: - Spreadsheet management

    private func findOrCreateSpreadsheet() async throws -> String {
        // Search for the spreadsheet anywhere in Drive (name is unique enough)
        if let id = try await findSpreadsheet() {
            return id
        }
        // Sheet doesn't exist — create it inside the Receipts folder
        let receiptsFolderId = try await findReceiptsFolder()
        let spreadsheetId = try await createSpreadsheet(in: receiptsFolderId)
        try await writeHeaders(to: spreadsheetId)
        return spreadsheetId
    }

    private func findSpreadsheet() async throws -> String? {
        let escaped = spreadsheetName.replacingOccurrences(of: "'", with: "\\'")
        let query = "name='\(escaped)' and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false"

        var components = URLComponents(url: driveFilesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]
        let data = try await perform(try await authorizedRequest(url: components.url!, method: "GET"))
        struct Response: Decodable {
            struct File: Decodable { let id: String }
            let files: [File]
        }
        return try JSONDecoder().decode(Response.self, from: data).files.first?.id
    }

    private func findReceiptsFolder() async throws -> String {
        let query = "name='Receipts' and 'root' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        var components = URLComponents(url: driveFilesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]
        let data = try await perform(try await authorizedRequest(url: components.url!, method: "GET"))
        struct Response: Decodable {
            struct File: Decodable { let id: String }
            let files: [File]
        }
        guard let id = try JSONDecoder().decode(Response.self, from: data).files.first?.id else {
            throw ReceiptVaultError.uploadFailure("Receipts folder not found. Upload a receipt first.")
        }
        return id
    }

    private func createSpreadsheet(in folderId: String) async throws -> String {
        let metadata: [String: Any] = [
            "name": spreadsheetName,
            "mimeType": "application/vnd.google-apps.spreadsheet",
            "parents": [folderId]
        ]
        var request = try await authorizedRequest(url: driveFilesURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let data = try await perform(request)
        struct Response: Decodable { let id: String }
        return try JSONDecoder().decode(Response.self, from: data).id
    }

    private func writeHeaders(to spreadsheetId: String) async throws {
        let headers = ["date", "shopName", "total", "currency", "lineItems", "driveFileId", "driveFilePath", "scannedAt"]
        try await writeValues(to: spreadsheetId, range: "Sheet1!A1", values: [headers], inputOption: "RAW")
    }

    // MARK: - Row append

    private func appendRow(to spreadsheetId: String, receiptData: ReceiptData, driveFileId: String, driveFilePath: String) async throws {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        let lineItemsJSON = (try? String(data: JSONEncoder().encode(receiptData.lineItems), encoding: .utf8)) ?? "[]"
        let total = (receiptData.total as NSDecimalNumber?)?.doubleValue as Any? ?? ""

        let row: [Any] = [
            df.string(from: receiptData.date),
            receiptData.shopName,
            total,
            receiptData.currency ?? "",
            lineItemsJSON,
            driveFileId,
            driveFilePath,
            ISO8601DateFormatter().string(from: Date())
        ]

        let urlString = "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/Sheet1:append"
        guard let url = URL(string: urlString) else {
            throw ReceiptVaultError.uploadFailure("Invalid Sheets URL")
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "USER_ENTERED"),
            URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS")
        ]
        var request = try await authorizedRequest(url: components.url!, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["values": [row]])
        _ = try await perform(request)
    }

    // MARK: - Helpers

    private func writeValues(to spreadsheetId: String, range: String, values: [[Any]], inputOption: String) async throws {
        let urlString = "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(range)"
        guard let url = URL(string: urlString) else { return }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "valueInputOption", value: inputOption)]

        var request = try await authorizedRequest(url: components.url!, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["values": values])
        _ = try await perform(request)
    }

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
            throw ReceiptVaultError.uploadFailure("Sheets API error \(status): \(body)")
        }
        return data
    }
}

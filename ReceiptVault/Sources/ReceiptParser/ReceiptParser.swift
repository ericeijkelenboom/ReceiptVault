import UIKit

final class ReceiptParser {
    private let lambdaEndpoint: URL

    init() {
        self.lambdaEndpoint = URL(string: Config.lambdaEndpoint) ?? URL(fileURLWithPath: "")
    }

    func parse(image: UIImage) async throws -> ReceiptData {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw ReceiptVaultError.parseFailure("Failed to encode image as JPEG")
        }

        let base64Image = imageData.base64EncodedString()

        // Prepare request to Lambda backend
        var request = URLRequest(url: lambdaEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "imageBase64": base64Image
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Call Lambda endpoint
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw ReceiptVaultError.parseFailure("Invalid response from Lambda")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? "(empty)"
            throw ReceiptVaultError.parseFailure("Lambda error \(httpResponse.statusCode): \(body)")
        }

        // Parse Lambda response
        return try decodeReceiptData(from: responseData)
    }

    // MARK: - Response Parsing

    private func decodeReceiptData(from data: Data) throws -> ReceiptData {
        // Check for the non-receipt signal before attempting full decode
        struct NotReceiptDTO: Decodable { let notAReceipt: Bool? }
        if (try? JSONDecoder().decode(NotReceiptDTO.self, from: data))?.notAReceipt == true {
            throw ReceiptVaultError.parseFailure("This image doesn't appear to be a receipt.")
        }

        // DTO to handle Lambda returning numbers as Double and dates as strings
        struct DTO: Decodable {
            struct LineItemDTO: Decodable {
                let name: String
                let quantity: Double?
                let unitPrice: Double?
                let totalPrice: Double?
            }
            let shopName: String
            let date: String?
            let total: Double?
            let currency: String?
            let lineItems: [LineItemDTO]
            let rawText: String
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dto = try decoder.decode(DTO.self, from: data)

        guard !dto.shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReceiptVaultError.parseFailure("Could not determine shop name from receipt.")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let date: Date
        if let dateString = dto.date {
            guard let parsed = dateFormatter.date(from: dateString) else {
                throw ReceiptVaultError.parseFailure("Could not read receipt date: \(dateString)")
            }
            date = parsed
        } else {
            date = Date() // no date visible on receipt; fall back to today
        }

        let lineItems = dto.lineItems.map {
            LineItem(
                name: $0.name,
                quantity: $0.quantity.map { Decimal($0) },
                unitPrice: $0.unitPrice.map { Decimal($0) },
                totalPrice: $0.totalPrice.map { Decimal($0) }
            )
        }

        return ReceiptData(
            shopName: dto.shopName,
            date: date,
            total: dto.total.map { Decimal($0) },
            currency: dto.currency,
            lineItems: lineItems,
            rawText: dto.rawText
        )
    }
}

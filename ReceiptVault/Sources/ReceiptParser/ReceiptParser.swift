import UIKit

final class ReceiptParser {
    private let apiEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-20250514"
    private let anthropicVersion = "2023-06-01"

    func parse(image: UIImage) async throws -> ReceiptData {
        guard let apiKey = KeychainHelper.read(key: "anthropic_api_key"), !apiKey.isEmpty else {
            throw ReceiptVaultError.authRequired
        }

        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw ReceiptVaultError.parseFailure("Failed to encode image as JPEG")
        }

        let request = try buildRequest(apiKey: apiKey, base64Image: imageData.base64EncodedString())
        let (responseData, urlResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw ReceiptVaultError.parseFailure("Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? "(empty)"
            throw ReceiptVaultError.parseFailure("API error \(httpResponse.statusCode): \(body)")
        }

        return try extractReceiptData(from: responseData)
    }

    // MARK: - Request

    private func buildRequest(apiKey: String, base64Image: String) throws -> URLRequest {
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": Self.extractionPrompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    // MARK: - Response Parsing

    private func extractReceiptData(from data: Data) throws -> ReceiptData {
        struct AnthropicResponse: Decodable {
            struct ContentBlock: Decodable {
                let type: String
                let text: String?
            }
            let content: [ContentBlock]
        }

        let envelope = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        guard let text = envelope.content.first(where: { $0.type == "text" })?.text else {
            throw ReceiptVaultError.parseFailure("No text content in API response")
        }

        // Strip markdown code fences if the model wraps the JSON
        let jsonString = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```json\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ReceiptVaultError.parseFailure("Could not re-encode response JSON")
        }

        return try decodeReceiptData(from: jsonData)
    }

    private func decodeReceiptData(from data: Data) throws -> ReceiptData {
        // DTO to handle Claude returning numbers as Double and dates as strings
        struct DTO: Decodable {
            struct LineItemDTO: Decodable {
                let name: String
                let quantity: Double?
                let unitPrice: Double?
                let totalPrice: Double?
            }
            let shopName: String
            let date: String
            let total: Double?
            let currency: String?
            let lineItems: [LineItemDTO]
            let rawText: String
        }

        let dto = try JSONDecoder().decode(DTO.self, from: data)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let date = dateFormatter.date(from: dto.date) ?? Date()

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

    // MARK: - Prompt

    private static let extractionPrompt = """
    Extract all information from this receipt image and return it as a JSON object with exactly \
    this structure. Return ONLY the JSON — no explanation, no markdown fences.

    {
      "shopName": "store or restaurant name",
      "date": "YYYY-MM-DD",
      "total": 0.00,
      "currency": "USD",
      "lineItems": [
        {
          "name": "item description",
          "quantity": 1,
          "unitPrice": 0.00,
          "totalPrice": 0.00
        }
      ],
      "rawText": "all visible text from the receipt verbatim"
    }

    Rules:
    - date: use the date printed on the receipt in YYYY-MM-DD format
    - total: the final amount paid (after tax and discounts), as a number
    - currency: 3-letter ISO 4217 code (USD, EUR, GBP, etc.) — infer from symbol or locale if not explicit
    - lineItems: individual product/service lines only; omit subtotals, taxes, tips, and fees
    - quantity/unitPrice/totalPrice: use null if not shown on the receipt
    - rawText: verbatim transcription of every visible character on the receipt
    """
}

import Foundation

@MainActor
final class ReceiptStore: ObservableObject {
    @Published private(set) var receipts: [CachedReceipt] = []

    private let cacheURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheURL = docs.appendingPathComponent("receipts_cache.json")
        load()
    }

    // MARK: - Public

    func add(_ receipt: CachedReceipt) {
        guard !receipts.contains(where: { $0.driveFileId == receipt.driveFileId }) else { return }
        receipts.append(receipt)
        receipts.sort { $0.date > $1.date }
        save()
    }

    func delete(_ receipt: CachedReceipt, authManager: AuthManager) async throws {
        receipts.removeAll { $0.driveFileId == receipt.driveFileId }
        save()
        let uploader = DriveUploader(authManager: authManager)
        try await uploader.deleteReceipt(driveFileId: receipt.driveFileId)
        let logger = SheetsLogger(authManager: authManager)
        try await logger.deleteRow(driveFileId: receipt.driveFileId)
    }

    func syncFromDrive(authManager: AuthManager) async throws {
        let uploader = DriveUploader(authManager: authManager)
        let fetched = try await uploader.fetchAllReceipts()
        receipts = fetched.sorted { $0.date > $1.date }
        save()
    }

    // MARK: - Grouped

    var groupedByMonth: [(title: String, receipts: [CachedReceipt])] {
        grouped(searchText: "")
    }

    func grouped(searchText: String = "") -> [(title: String, receipts: [CachedReceipt])] {
        let source: [CachedReceipt]
        if searchText.isEmpty {
            source = receipts
        } else {
            let q = searchText.lowercased()
            source = receipts.filter { $0.matches(query: q) }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: source) { receipt -> Date in
            let comps = calendar.dateComponents([.year, .month], from: receipt.date)
            return calendar.date(from: comps) ?? receipt.date
        }

        return grouped
            .map { (monthDate, monthReceipts) in
                (title: formatter.string(from: monthDate),
                 receipts: monthReceipts.sorted { $0.date > $1.date })
            }
            .sorted { ($0.receipts.first?.date ?? .distantPast) > ($1.receipts.first?.date ?? .distantPast) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        receipts = (try? decoder.decode([CachedReceipt].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(receipts) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

// MARK: - Search matching

private extension CachedReceipt {
    func matches(query: String) -> Bool {
        if shopName.lowercased().contains(query) { return true }
        if lineItems.contains(where: { $0.name.lowercased().contains(query) }) { return true }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in ["MMMM yyyy", "MMMM", "yyyy", "yyyy-MM-dd"] {
            df.dateFormat = format
            if df.string(from: date).lowercased().contains(query) { return true }
        }
        return false
    }
}

import Foundation

@MainActor
class QuotaManager: ObservableObject {
    @Published var receiptsUsedThisMonth = 0
    @Published var maxReceiptsPerMonth = 3

    private let userDefaults = UserDefaults.standard

    init() {
        loadState()
    }

    func canAddReceipt() -> Bool {
        checkAndResetIfNewMonth()
        return receiptsUsedThisMonth < maxReceiptsPerMonth
    }

    func recordReceiptAdded() {
        checkAndResetIfNewMonth()
        receiptsUsedThisMonth += 1
        saveState()
    }

    func getRemainingReceipts() -> Int {
        checkAndResetIfNewMonth()
        return max(0, maxReceiptsPerMonth - receiptsUsedThisMonth)
    }

    private func getMonthString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func checkAndResetIfNewMonth() {
        let currentMonth = getMonthString()
        let lastMonth = userDefaults.string(forKey: "quotaMonth") ?? ""

        if currentMonth != lastMonth {
            receiptsUsedThisMonth = 0
            userDefaults.set(currentMonth, forKey: "quotaMonth")
        }
    }

    private func loadState() {
        let currentMonth = getMonthString()
        let lastMonth = userDefaults.string(forKey: "quotaMonth") ?? ""

        if currentMonth == lastMonth {
            receiptsUsedThisMonth = userDefaults.integer(forKey: "receiptsUsedThisMonth")
        } else {
            receiptsUsedThisMonth = 0
            saveState()
        }
    }

    private func saveState() {
        userDefaults.set(receiptsUsedThisMonth, forKey: "receiptsUsedThisMonth")
        userDefaults.set(getMonthString(), forKey: "quotaMonth")
    }
}

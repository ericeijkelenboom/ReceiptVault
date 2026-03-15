import SwiftUI

struct ReceiptEditView: View {
    @Environment(\.dismiss) private var dismiss

    let original: CachedReceipt
    let onSave: (CachedReceipt) -> Void

    @State private var shopName: String
    @State private var date: Date
    @State private var totalString: String
    @State private var currency: String

    init(receipt: CachedReceipt, onSave: @escaping (CachedReceipt) -> Void) {
        self.original = receipt
        self.onSave = onSave
        _shopName = State(initialValue: receipt.shopName)
        _date = State(initialValue: receipt.date)
        _totalString = State(initialValue: receipt.total.map { "\($0)" } ?? "")
        _currency = State(initialValue: receipt.currency ?? "")
    }

    private var canSave: Bool {
        !shopName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shop") {
                    TextField("Shop name", text: $shopName)
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(.brandPrimary)
                }
                Section("Total") {
                    TextField("Amount", text: $totalString)
                        .keyboardType(.decimalPad)
                    TextField("Currency (e.g. DKK)", text: $currency)
                        .onChange(of: currency) { _, new in
                            currency = String(new.prefix(3)).uppercased()
                        }
                }
            }
            .navigationTitle("Edit Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let normalized = totalString.replacingOccurrences(of: ",", with: ".")
        let parsedTotal = Decimal(string: normalized)
        let updated = CachedReceipt(
            id: original.id,
            shopName: shopName.trimmingCharacters(in: .whitespaces),
            date: date,
            total: parsedTotal,
            currency: currency.isEmpty ? nil : currency,
            scannedAt: original.scannedAt,
            lineItems: original.lineItems
        )
        onSave(updated)
        dismiss()
    }
}

#Preview {
    ReceiptEditView(
        receipt: CachedReceipt(
            id: UUID(),
            shopName: "Sports World",
            date: .now,
            total: 429.00,
            currency: "DKK",
            scannedAt: .now
        ),
        onSave: { _ in }
    )
}

import SwiftUI

struct ReceiptEditView: View {
    @Environment(\.dismiss) private var dismiss

    let original: CachedReceipt
    let onSave: (CachedReceipt) -> Void

    @State private var shopName: String
    @State private var date: Date
    @State private var totalString: String
    @State private var currency: String
    @State private var lineItems: [EditableLineItem]
    @State private var showDatePicker = false

    init(receipt: CachedReceipt, onSave: @escaping (CachedReceipt) -> Void) {
        self.original = receipt
        self.onSave = onSave
        _shopName = State(initialValue: receipt.shopName)
        _date = State(initialValue: receipt.date)
        _totalString = State(initialValue: receipt.total.map { "\($0)" } ?? "")
        _currency = State(initialValue: receipt.currency ?? "")
        _lineItems = State(initialValue: receipt.lineItems.map { EditableLineItem(from: $0) })
    }

    private var canSave: Bool {
        !shopName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    shopNameSection
                    dateSection
                    totalSection
                    itemsSection
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? Color.brandPrimary : Color(.tertiaryLabel))
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var shopNameSection: some View {
        EditSection(label: "SHOP NAME") {
            TextField("Shop name", text: $shopName)
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(10)
        }
    }

    private var dateSection: some View {
        EditSection(label: "DATE") {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDatePicker.toggle() }
                } label: {
                    HStack {
                        Text(date.formatted(.dateTime.day().month().year()))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(showDatePicker ? 0 : 10)
                }
                .buttonStyle(.plain)

                if showDatePicker {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color.brandPrimary)
                        .padding(.horizontal, 8)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var totalSection: some View {
        EditSection(label: "TOTAL AMOUNT") {
            HStack(spacing: 8) {
                TextField("0.00", text: $totalString)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)

                TextField("DKK", text: $currency)
                    .onChange(of: currency) { _, new in
                        currency = String(new.prefix(3)).uppercased()
                    }
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .frame(width: 80)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            }
        }
    }

    private var itemsSection: some View {
        EditSection(label: "ITEMS (\(lineItems.count))") {
            VStack(spacing: 0) {
                if !lineItems.isEmpty {
                    VStack(spacing: 0) {
                        ForEach($lineItems) { $item in
                            if item.id != lineItems.first?.id {
                                Divider().padding(.leading, 52)
                            }
                            EditableItemRow(item: $item) {
                                lineItems.removeAll { $0.id == item.id }
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .padding(.bottom, 8)
                }

                Button {
                    lineItems.append(EditableLineItem())
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add Item")
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.brandPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandPrimary.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let normalized = totalString.replacingOccurrences(of: ",", with: ".")
        let parsedTotal = Decimal(string: normalized)
        // Items with blank names are dropped. Items with unparseable prices get nil totalPrice.
        let savedItems = lineItems.compactMap { $0.toLineItem() }
        let updated = CachedReceipt(
            id: original.id,
            shopName: shopName.trimmingCharacters(in: .whitespaces),
            date: date,
            total: parsedTotal,
            currency: currency.isEmpty ? nil : currency,
            scannedAt: original.scannedAt,
            lineItems: savedItems
        )
        onSave(updated)
        dismiss()
    }
}

// MARK: - EditSection helper

private struct EditSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Editable item row

private struct EditableItemRow: View {
    @Binding var item: EditableLineItem
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDelete) {
                ZStack {
                    Circle()
                        .fill(Color(.systemRed).opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)

            TextField("Item name", text: $item.name)
                .font(.body)

            Spacer()

            TextField("0.00", text: $item.priceString)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body)
                .frame(width: 72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - EditableLineItem (view-local model)
// Bridges between LineItem (immutable model) and editable text fields.
// toLineItem() returns nil for blank-name items (they are dropped on save).
// An invalid price string produces a nil totalPrice — it does not block saving.

struct EditableLineItem: Identifiable {
    let id: UUID
    var name: String
    var priceString: String

    /// New blank item
    init() {
        id = UUID()
        name = ""
        priceString = ""
    }

    /// Initialize from an existing LineItem, preserving its UUID
    init(from item: LineItem) {
        id = item.id
        name = item.name
        priceString = item.totalPrice.map { "\($0)" } ?? ""
    }

    /// Returns nil if name is blank (item will be dropped from the saved receipt).
    func toLineItem() -> LineItem? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let normalized = priceString.replacingOccurrences(of: ",", with: ".")
        let price = Decimal(string: normalized) // nil if string is not a valid decimal
        return LineItem(name: trimmed, totalPrice: price, id: id)
    }
}

#Preview {
    ReceiptEditView(
        receipt: CachedReceipt(
            id: UUID(),
            shopName: "7-Eleven",
            date: .now,
            total: 62.00,
            currency: "DKK",
            scannedAt: .now,
            lineItems: [
                LineItem(name: "Latte Medium", totalPrice: 38.00),
                LineItem(name: "Croissant", totalPrice: 24.00),
            ]
        ),
        onSave: { _ in }
    )
}

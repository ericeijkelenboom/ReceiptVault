import SwiftUI

struct ReceiptDetailView: View {
    @EnvironmentObject private var receiptStore: ReceiptStoreCore
    @State private var receipt: CachedReceipt
    @State private var showEdit = false
    @State private var editError: String?

    init(receipt: CachedReceipt) {
        _receipt = State(initialValue: receipt)
    }

    var body: some View {
        List {
            headerSection
            infoSection
            lineItemsSection
            actionsSection
        }
        .navigationTitle(receipt.shopName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                ReceiptEditView(receipt: receipt) { updated in
                    Task {
                        do {
                            try await receiptStore.update(updated)
                            receipt = updated
                        } catch {
                            editError = error.localizedDescription
                        }
                    }
                }
                .navigationTitle("Edit Receipt")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Error", isPresented: .constant(editError != nil), actions: {
            Button("OK") { editError = nil }
        }, message: {
            Text(editError ?? "")
        })
    }

    private var headerSection: some View {
        Section {
            Button(action: { showEdit = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.shopName)
                            .font(.headline)
                        Text(receipt.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundStyle(.blue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var infoSection: some View {
        Section("Details") {
            if let total = receipt.total, let currency = receipt.currency {
                LabeledContent("Total", value: (total as NSDecimalNumber as Decimal).formatted(.currency(code: currency)))
            }
        }
    }

    private var lineItemsSection: some View {
        Section("Items") {
            if receipt.lineItems.isEmpty {
                Text("No items extracted")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(receipt.lineItems, id: \.name) { item in
                    lineItemRow(item)
                }
            }
        }
    }

    private func lineItemRow(_ item: LineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.body)
            HStack {
                if let qty = item.quantity {
                    Text("Qty: \(qty.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let price = item.totalPrice {
                    Spacer()
                    Text(price.description)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                Task {
                    do {
                        try await receiptStore.deleteReceipt(id: receipt.id)
                    } catch {
                        editError = error.localizedDescription
                    }
                }
            } label: {
                Label("Delete Receipt", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReceiptDetailView(receipt: CachedReceipt(
            id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            shopName: "Whole Foods",
            date: Date(),
            total: 47.20,
            currency: "USD",
            scannedAt: Date(),
            lineItems: [
                LineItem(name: "Organic Bananas", quantity: 1, unitPrice: 3.99, totalPrice: 3.99),
                LineItem(name: "Greek Yogurt", quantity: 2, unitPrice: 5.99, totalPrice: 11.98),
            ]
        ))
        .environmentObject(ReceiptStoreCore())
    }
}

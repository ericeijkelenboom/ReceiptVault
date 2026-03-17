import SwiftUI

struct ReceiptDetailView: View {
    @EnvironmentObject private var receiptStore: ReceiptStoreCore
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: CachedReceipt
    @State private var showEdit = false
    @State private var editError: String?
    @State private var showDeleteConfirmation = false

    init(receipt: CachedReceipt) {
        _receipt = State(initialValue: receipt)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                receiptImageCard
                itemsCard
                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
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
        }
        .alert("Error", isPresented: Binding(get: { editError != nil }, set: { if !$0 { editError = nil } }), actions: {
            Button("OK") { editError = nil }
        }, message: {
            Text(editError ?? "")
        })
        .alert("Delete Receipt?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await receiptStore.deleteReceipt(id: receipt.id)
                        dismiss()
                    } catch {
                        editError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(receipt.deleteConfirmationMessage)
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(receipt.shopName)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(receipt.date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            Divider()

            VStack(spacing: 4) {
                Text("TOTAL")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)

                if let total = receipt.total, let currency = receipt.currency {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(total as NSDecimalNumber as Decimal,
                             format: .number.precision(.fractionLength(2)))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Color.brandPrimary)
                            .monospacedDigit()
                        Text(currency)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Receipt Image Placeholder
    // TODO: Future feature — store the original JPEG alongside the Core Data record.
    // Steps needed:
    //   1. Save image to app documents dir in ProcessingPipeline, store path in CachedReceipt
    //   2. Display a thumbnail here (Image from file path)
    //   3. On tap, open a full-screen image viewer (QuickLook or custom ZoomableImageView)
    // See: ReceiptStoreCore.saveReceipt — add imagePath parameter

    private var receiptImageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECEIPT IMAGE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(height: 160)
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(.systemGray3))
                    Text("Scanned receipt")
                        .font(.caption)
                        .foregroundStyle(Color(.systemGray3))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Items Card

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ITEMS (\(receipt.lineItems.count))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if receipt.lineItems.isEmpty {
                Text("No items extracted")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ForEach(receipt.lineItems) { item in
                    Divider().padding(.horizontal, 16)
                    HStack {
                        Text(item.name)
                            .font(.body)
                        Spacer()
                        if let price = item.totalPrice {
                            Text(price as NSDecimalNumber as Decimal,
                                 format: .number.precision(.fractionLength(2)))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if let total = receipt.total, let currency = receipt.currency {
                    Divider().padding(.horizontal, 16)
                    HStack {
                        Text("Total")
                            .font(.body)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(total as NSDecimalNumber as Decimal,
                             format: .currency(code: currency))
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.brandPrimary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete Receipt")
            }
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ReceiptDetailView(receipt: CachedReceipt(
            id: UUID(),
            shopName: "7-Eleven",
            date: Date(),
            total: 62.00,
            currency: "DKK",
            scannedAt: Date(),
            lineItems: [
                LineItem(name: "Latte Medium", totalPrice: 38.00),
                LineItem(name: "Croissant", totalPrice: 24.00),
            ]
        ))
        .environmentObject(ReceiptStoreCore())
    }
}

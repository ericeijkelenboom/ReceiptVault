import SwiftUI
import PDFKit

struct ReceiptDetailView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var receiptStore: ReceiptStoreCore
    @State private var receipt: CachedReceipt
    @State private var showPDFFullScreen = false
    @State private var showEdit = false
    @State private var pdfData: Data?
    @State private var pdfError: String?
    @State private var editError: String?

    init(receipt: CachedReceipt) {
        _receipt = State(initialValue: receipt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                thumbnailSection
                infoSection
                lineItemsSection
            }
            .padding()
        }
        .navigationTitle(receipt.shopName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            ReceiptEditView(receipt: receipt) { updated in
                receipt = updated
                Task {
                    do {
                        try await receiptStore.update(updated)
                    } catch {
                        await MainActor.run { editError = error.localizedDescription }
                    }
                }
            }
        }
        .alert("Sync Failed", isPresented: Binding(
            get: { editError != nil },
            set: { if !$0 { editError = nil } }
        )) {
            Button("OK", role: .cancel) { editError = nil }
        } message: {
            Text(editError ?? "")
        }
        .fullScreenCover(isPresented: $showPDFFullScreen) {
            ZStack(alignment: .topTrailing) {
                if let data = pdfData {
                    ReceiptPDFViewer(pdfData: data)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                    ProgressView("Loading PDF…")
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button {
                    showPDFFullScreen = false
                    pdfData = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .padding()
                }
            }
        }
    }

    // MARK: - Sections

    private var thumbnailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt")
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)
            Button {
                showPDFFullScreen = true
                Task { await loadPDF() }
            } label: {
                ReceiptThumbnailView(driveFileId: receipt.driveFileId, authManager: authManager)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Shop", receipt.shopName)
                infoRow("Date", receipt.date.formatted(date: .long, time: .omitted))
                if let total = receipt.total, let currency = receipt.currency {
                    infoRow("Total", (total as NSDecimalNumber as Decimal).formatted(.currency(code: currency)))
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Line Items")
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)
            if receipt.lineItems.isEmpty {
                Text("No line items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(receipt.lineItems.enumerated()), id: \.offset) { index, item in
                        LineItemRow(item: item, currency: receipt.currency)
                        if index < receipt.lineItems.count - 1 {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    // MARK: - PDF

    @MainActor
    private func loadPDF() async {
        guard pdfData == nil else { return }
        do {
            let uploader = DriveUploader(authManager: authManager)
            pdfData = try await uploader.downloadFile(fileId: receipt.driveFileId)
        } catch {
            pdfError = error.localizedDescription
        }
    }
}

// MARK: - Receipt Thumbnail

private struct ReceiptThumbnailView: View {
    let driveFileId: String
    let authManager: AuthManager
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(3/4, contentMode: .fit)
                    .overlay { ProgressView() }
            } else if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(3/4, contentMode: .fit)
                    .overlay {
                        Image(systemName: "doc.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let uploader = DriveUploader(authManager: authManager)
            let data = try await uploader.downloadFile(fileId: driveFileId)
            if let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) {
                let pageRect = page.bounds(for: .mediaBox)
                let scale: CGFloat = 300 / max(pageRect.width, pageRect.height)
                let thumbRect = CGRect(x: 0, y: 0, width: pageRect.width * scale, height: pageRect.height * scale)
                let renderer = UIGraphicsImageRenderer(size: thumbRect.size)
                thumbnailImage = renderer.image { ctx in
                    UIColor.white.set()
                    ctx.fill(thumbRect)
                    ctx.cgContext.translateBy(x: 0, y: thumbRect.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)
                    ctx.cgContext.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
            }
        } catch {
            thumbnailImage = nil
        }
    }
}

// MARK: - Line Item Row

private struct LineItemRow: View {
    let item: LineItem
    let currency: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                if let qty = item.quantity, qty != 1 {
                    Text(verbatim: "Qty: \(qty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let price = item.totalPrice ?? item.unitPrice, let code = currency {
                Text((price as NSDecimalNumber as Decimal).formatted(.currency(code: code)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReceiptDetailView(receipt: CachedReceipt(
            driveFileId: "preview",
            shopName: "Whole Foods",
            date: .now,
            total: 47.20,
            currency: "USD",
            scannedAt: .now,
            lineItems: [
                LineItem(name: "Organic Milk", quantity: 1, unitPrice: 4.99, totalPrice: 4.99),
                LineItem(name: "Sourdough Bread", quantity: 2, unitPrice: 6.49, totalPrice: 12.98)
            ]
        ))
        .environmentObject(AuthManager())
        .environmentObject(ReceiptStore())
    }
}

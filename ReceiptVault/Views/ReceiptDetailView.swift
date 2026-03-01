import SwiftUI
import PDFKit

struct ReceiptDetailView: View {
    let receipt: CachedReceipt
    @EnvironmentObject private var authManager: AuthManager
    @State private var detail: ReceiptDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPDFFullScreen = false
    @State private var pdfData: Data?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading receipt…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Could not load receipt", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if let detail {
                detailContent(detail)
            } else {
                ContentUnavailableView("Receipt not found", systemImage: "doc.questionmark")
            }
        }
        .navigationTitle(receipt.shopName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .fullScreenCover(isPresented: $showPDFFullScreen) {
            ZStack(alignment: .topTrailing) {
                if let data = pdfData {
                    ReceiptPDFViewer(pdfData: data)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                    ProgressView("Loading receipt…")
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

    @ViewBuilder
    private func detailContent(_ detail: ReceiptDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                receiptThumbnailSection(detail)
                receiptInfoSection(detail)
                lineItemsSection(detail)
            }
            .padding()
        }
    }

    private func receiptThumbnailSection(_ detail: ReceiptDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt")
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)
            Button {
                showPDFFullScreen = true
                Task { await loadPDF() }
            } label: {
                ReceiptThumbnailView(driveFileId: detail.driveFileId, authManager: authManager)
            }
            .buttonStyle(.plain)
        }
    }

    private func receiptInfoSection(_ detail: ReceiptDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Shop", detail.shopName)
                infoRow("Date", detail.date.formatted(date: .long, time: .omitted))
                if let total = detail.total, let currency = detail.currency {
                    infoRow("Total", (total as NSDecimalNumber as Decimal).formatted(.currency(code: currency)))
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func lineItemsSection(_ detail: ReceiptDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Line Items")
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)
            if detail.lineItems.isEmpty {
                Text("No line items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(detail.lineItems) { item in
                        LineItemRow(item: item, currency: detail.currency)
                        if item.id != detail.lineItems.last?.id {
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
        }
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let uploader = DriveUploader(authManager: authManager)
            detail = try await uploader.fetchReceiptDetails(driveFileId: receipt.driveFileId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadPDF() async {
        do {
            let uploader = DriveUploader(authManager: authManager)
            let data = try await uploader.downloadFile(fileId: receipt.driveFileId)
            pdfData = data
        } catch {
            errorMessage = error.localizedDescription
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
                    .overlay {
                        ProgressView()
                    }
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
        .frame(maxHeight: 200)
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
    let item: ReceiptDetailLineItem
    let currency: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                if let qty = item.quantity, qty != 1 {
                    Text("Qty: \(qty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let price = item.totalPrice ?? item.unitPrice, let code = currency {
                Text((price as NSDecimalNumber as Decimal).formatted(.currency(code: code)))
                    .font(.subheadline)
                    .fontWeight(.medium)
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
            scannedAt: .now
        ))
        .environmentObject(AuthManager())
    }
}

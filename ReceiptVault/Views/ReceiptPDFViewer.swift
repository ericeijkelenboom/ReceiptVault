import SwiftUI
import PDFKit

struct ReceiptPDFViewer: View {
    let pdfData: Data

    var body: some View {
        PDFKitView(data: pdfData)
    }
}

// MARK: - PDFKit UIViewRepresentable with zoom support

private struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.minScaleFactor = 0.5
        pdfView.maxScaleFactor = 4.0
        pdfView.backgroundColor = .systemBackground
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil, let document = PDFDocument(data: data) {
            pdfView.document = document
        }
    }
}

#Preview {
    ReceiptPDFViewer(pdfData: Data())
}

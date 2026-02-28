import UIKit
import CoreText

final class PDFBuilder {
    /// Builds a searchable PDF: the receipt image as the visual layer,
    /// with an invisible CoreText layer so the text is selectable/searchable.
    func build(image: UIImage, receiptData: ReceiptData) async throws -> Data {
        let pageRect = pageRect(for: image)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()

            // Layer 1: image
            image.draw(in: pageRect)

            // Layer 2: invisible text for search and copy
            drawInvisibleText(receiptData.rawText, in: pageRect, context: ctx.cgContext)
        }
    }

    // MARK: - Private

    private func pageRect(for image: UIImage) -> CGRect {
        // Cap to A4 at 150 dpi (1240 x 1754 pt) so the PDF stays a reasonable size
        let maxWidth: CGFloat = 1240
        let maxHeight: CGFloat = 1754
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height, 1.0)
        return CGRect(
            origin: .zero,
            size: CGSize(width: image.size.width * scale, height: image.size.height * scale)
        )
    }

    private func drawInvisibleText(_ text: String, in rect: CGRect, context: CGContext) {
        context.saveGState()

        // UIGraphicsPDFRenderer uses UIKit coordinates (origin top-left, y down).
        // CoreText expects CG coordinates (origin bottom-left, y up), so flip.
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)

        // Invisible text rendering mode: text is encoded in the PDF content stream
        // (making it selectable and searchable) but not painted on screen.
        context.setTextDrawingMode(.invisible)

        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attrString = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, context)

        context.restoreGState()
    }
}

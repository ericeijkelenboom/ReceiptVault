import UIKit
import CoreText

final class PDFBuilder {
    /// Builds a searchable PDF: the receipt image as the visual layer,
    /// with an invisible CoreText layer so the text is selectable/searchable.
    func build(image: UIImage, receiptData: ReceiptData) async throws -> Data {
        // Downscale before embedding. Camera photos are 12MP+; receipts are
        // readable at ~200 DPI on a 3.5" wide slip, so 1200px on the long
        // edge is more than sufficient and keeps the PDF well under 300 KB.
        let scaledImage = resized(image, maxDimension: 1200)
        let pageRect = CGRect(origin: .zero, size: scaledImage.size)

        // Force 1× scale so UIGraphicsPDFRenderer doesn't apply the device's
        // 2× or 3× Retina multiplier to the embedded raster data.
        let format = UIGraphicsPDFRendererFormat.default()
        format.scale = 1.0

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { ctx in
            ctx.beginPage()

            // Layer 1: image
            scaledImage.draw(in: pageRect)

            // Layer 2: invisible text for search and copy
            drawInvisibleText(receiptData.rawText, in: pageRect, context: ctx.cgContext)
        }
    }

    // MARK: - Private

    /// Returns a copy of `image` scaled so its longest edge is at most `maxDimension`
    /// pixels. Uses an explicit 1× renderer so the result has no Retina multiplier.
    private func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
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

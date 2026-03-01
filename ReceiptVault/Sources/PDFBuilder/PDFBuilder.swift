import UIKit
import CoreText

final class PDFBuilder {
    /// Builds a searchable PDF: the receipt image as the visual layer,
    /// with an invisible CoreText layer so the text is selectable/searchable.
    func build(image: UIImage, receiptData: ReceiptData) async throws -> Data {
        // Resize to ≤1200px and re-encode as JPEG. When a JPEG-backed CGImage
        // is drawn into a PDF context, Core Graphics embeds the JPEG stream
        // directly rather than a raw bitmap, keeping file size small.
        let embeddedImage = jpegScaled(image, maxDimension: 1200, quality: 0.75)
        let pageRect = CGRect(origin: .zero, size: embeddedImage.size)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()

            // Layer 1: image
            embeddedImage.draw(in: pageRect)

            // Layer 2: invisible text for search and copy
            drawInvisibleText(receiptData.rawText, in: pageRect, context: ctx.cgContext)
        }
    }

    // MARK: - Private

    /// Resizes `image` so its longest edge is at most `maxDimension` pixels (using a
    /// 1× renderer to avoid a Retina multiplier), then re-encodes as JPEG at `quality`
    /// and wraps the result in a CGImage backed by that JPEG data provider.
    private func jpegScaled(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        guard let jpegData = resized.jpegData(compressionQuality: quality),
              let provider = CGDataProvider(data: jpegData as CFData),
              let cgImage = CGImage(jpegDataProviderSource: provider,
                                    decode: nil,
                                    shouldInterpolate: true,
                                    intent: .defaultIntent) else {
            return resized
        }
        return UIImage(cgImage: cgImage)
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

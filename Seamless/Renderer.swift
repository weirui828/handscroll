import UIKit
import CoreImage
import ImageIO

enum Renderer {
    static let jpegQuality: CGFloat = 0.95
    private static let ci = CIContext()

    /// Decodes with the camera rotation applied, capped to `cap` pixels.
    static func decode(_ data: Data, cap: CGFloat = maxPixels) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let scale = min(1, sqrt(cap / (w * h)))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: (max(w, h) * scale).rounded(),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// A copy whose longest side is at most `side`, for fast previews.
    static func downscaled(_ img: UIImage, side: CGFloat) -> UIImage {
        let longest = max(img.size.width, img.size.height)
        guard longest > side else { return img }
        let s = side / longest
        let size = CGSize(width: (img.size.width * s).rounded(), height: (img.size.height * s).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// A copy no larger than the size it will be drawn at, so CoreGraphics never samples
    /// a full-resolution photo down to one slide.
    static func sized(_ img: UIImage, covering size: CGSize) -> UIImage {
        let need = max(size.width, size.height)
        let have = max(img.size.width, img.size.height)
        guard need > 8, have > need * 1.1 else { return img }
        let s = need / have
        let target = CGSize(width: (img.size.width * s).rounded(), height: (img.size.height * s).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// A heavily blurred copy of the photo that covers the whole frame.
    static func blurred(_ photo: UIImage, size: CGSize) -> UIImage? {
        let h: CGFloat = 96
        let w = max(8, (h * size.width / size.height).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            let k = max(w / photo.size.width, h / photo.size.height)
            let dw = photo.size.width * k, dh = photo.size.height * k
            photo.draw(in: CGRect(x: (w - dw) / 2, y: (h - dh) / 2, width: dw, height: dh))
        }
        guard let input = CIImage(image: small) else { return nil }
        let out = input.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: input.extent)
        guard let cg = ci.createCGImage(out, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Draws the whole frame; `panel` selects one slide, or nil for the full strip.
    static func draw(photo: UIImage, geo: Geometry, layout: Layout, frame f: Frame,
                     look: Look, blur: UIImage?, panel: Int?) -> UIImage {
        let p = geo.place(layout, f)
        let size = panel == nil ? CGSize(width: f.fw, height: f.fh) : CGSize(width: f.pw, height: f.ph)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            let c = r.cgContext
            if let panel { c.translateBy(x: -CGFloat(panel) * f.pw, y: 0) }
            c.interpolationQuality = .high
            let all = CGRect(x: 0, y: 0, width: f.fw, height: f.fh)
            if geo.hasGap(p, f) {
                switch look.fill {
                case .blur:
                    blur?.draw(in: all)
                    if look.dim > 0 {
                        UIColor(white: 0, alpha: look.dim).setFill()
                        c.fill(all)
                    }
                case .black: UIColor.black.setFill(); c.fill(all)
                case .white: UIColor.white.setFill(); c.fill(all)
                case .color: UIColor(hex: look.colorHex).setFill(); c.fill(all)
                }
            }
            photo.draw(in: CGRect(x: p.x, y: p.y, width: p.dw, height: p.dh))
        }
    }

    /// One Drift frame at time t, `scale` times the 1080 × 1920 size.
    static func driftFrame(photo: UIImage, geo: Geometry, drift: DriftSettings, t: Double, scale: CGFloat) -> UIImage {
        let p = geo.driftPlace(drift, t: t)
        let size = CGSize(width: driftSize.width * scale, height: driftSize.height * scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            r.cgContext.interpolationQuality = .high
            photo.draw(in: CGRect(x: p.x * scale, y: p.y * scale, width: p.dw * scale, height: p.dh * scale))
        }
    }
}

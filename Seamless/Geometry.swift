import CoreGraphics
import Foundation

// Instagram keeps any feed ratio from 1.91:1 (wide) to 3:4 (tall, app uploads);
// 4:5 is the tallest that scheduling tools accept.
let minAspect: CGFloat = 3.0 / 4.0
let safeAspect: CGFloat = 4.0 / 5.0
let maxAspect: CGFloat = 1.91
let maxPixels: CGFloat = 24e6    // keeps the phone within its memory limits
let thumbPixels: CGFloat = 2e6   // batch previews only need a small copy
let maxSteps = 5
let maxPhotos = 10
let maxSlides = 5     // one image or up to five carousel slides
let driftSize = CGSize(width: 1080, height: 1920)
let driftFPS = 30

/// A window that should split into two panes: wide enough for both, and clearly
/// wider than tall so the split runs down the long edge.
func fitsTwoPanes(width: CGFloat, height: CGFloat, minWidth: CGFloat = 520) -> Bool {
    width >= minWidth && width > height * 1.05
}

enum Mode: String, CaseIterable, Identifiable, Codable {
    // Fit and Crop remain decodable for batches saved before Photo unified the editor.
    case split = "Split", fit = "Fit", crop = "Crop", drift = "Drift"   // shown as Video; the stored value stays for saved batches
    var id: String { rawValue }

    // Batches saved before the rename still hold "Carousel" and "Reel".
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "Carousel": self = .split
        case "Reel": self = .drift
        default:
            guard let mode = Mode(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown mode: \(raw)")
            }
            self = mode
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum Shape: String, CaseIterable, Identifiable, Codable {
    case auto = "Auto", r45 = "4:5", r34 = "3:4", r11 = "1:1"
    var id: String { rawValue }
    var aspect: CGFloat? {
        switch self {
        case .auto: nil
        case .r45: 4.0 / 5.0
        case .r34: 3.0 / 4.0
        case .r11: 1
        }
    }
}

enum Fill: String, CaseIterable, Identifiable, Codable {
    case blur = "Blur", black = "Black", white = "White", color = "Color"
    var id: String { rawValue }
}

/// How empty space around the photo is filled.
struct Look: Codable, Equatable {
    var fill = Fill.blur
    var colorHex = "#1A1A1A"
    var dim: CGFloat = 0.2
}

struct DriftSettings: Codable, Equatable {
    var dur: Double = 8
    var p0: Double = 0
    var p1: Double = 1
    var z0: Double = 1
    var z1: Double = 1.06
    var v: Double = 0.5
    var ease = true
}

/// One layout: n panels of a shape. Zoom 1 means the photo just covers the frame;
/// offsets are fractions of the frame.
struct Layout: Codable, Equatable {
    var n = 3
    var shape = Shape.auto
    var zoom: CGFloat = 1
    var ox: CGFloat = 0
    var oy: CGFloat = 0
    var nPicked = false
}

/// A step records one mode's settings. Zoom and position are relative, so they carry over to
/// other photos; Photo's slide count is nil (auto) unless a count was picked on purpose.
struct Step: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var type = Mode.split
    var shape = Shape.auto
    var n: Int?
    var zoom: CGFloat = 1
    var zoomContain = false
    var ox: CGFloat = 0
    var oy: CGFloat = 0
    var look = Look()
    var outW: CGFloat = 1080
    var drift = DriftSettings()

    // The video settings kept their old key on disk, so saved batches still decode.
    enum CodingKeys: String, CodingKey {
        case id, type, shape, n, zoom, zoomContain, ox, oy, look, outW
        case drift = "reel"
    }

    func sameAs(_ o: Step) -> Bool {
        var a = self, b = o
        a.id = ""; b.id = ""
        return a == b
    }

    var label: String {
        if type == .drift {
            let dir = drift.p1 > drift.p0 ? "left to right" : drift.p1 < drift.p0 ? "right to left" : "still"
            return "Video · \(Int(drift.dur)) s, \(dir)"
        }
        let s = shape == .auto ? "Auto" : shape.rawValue
        let count = type == .split ? n : 1
        return (count == 1 ? "Photo" : "Slides") + " · \(s)" +
            (count.flatMap { $0 > 1 ? " · \($0) slides" : nil } ?? "")
    }
}

/// What one batch photo uses for one step instead of the step's own settings.
struct Override {
    var layout: Layout?
    var look: Look?
    var drift: DriftSettings?
}

struct Frame {
    var a: CGFloat      // panel aspect (width / height)
    var pw: CGFloat     // panel size in output pixels
    var ph: CGFloat
    var n: Int
    var fw: CGFloat { pw * CGFloat(n) }
    var fh: CGFloat { ph }
}

struct Placement {
    var k: CGFloat
    var dw: CGFloat, dh: CGFloat
    var x: CGFloat, y: CGFloat
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

func ratioLabel(_ a: CGFloat) -> String {
    for s in Shape.allCases {
        if let v = s.aspect, abs(a - v) < 0.006 { return s.rawValue }
    }
    return String(format: "%.2f:1", a)
}

struct Geometry {
    let W: CGFloat
    let H: CGFloat

    func panelAspect(_ m: Layout) -> CGFloat {
        if let a = m.shape.aspect { return a }
        if m.n == 1 { return safeAspect }
        return clamp(W / (H * CGFloat(m.n)), minAspect, maxAspect)
    }

    func frame(_ m: Layout, outW: CGFloat) -> Frame {
        let a = panelAspect(m)
        return Frame(a: a, pw: outW, ph: (outW / a).rounded(), n: m.n)
    }

    func coverK(_ f: Frame) -> CGFloat { max(f.fw / W, f.fh / H) }
    func containK(_ f: Frame) -> CGFloat { min(f.fw / W, f.fh / H) }
    func zoomRange(_ f: Frame) -> ClosedRange<CGFloat> { (0.5 * containK(f) / coverK(f))...5 }
    func fitZoom(_ f: Frame) -> CGFloat { containK(f) / coverK(f) }
    func isNearFit(_ m: Layout, _ f: Frame) -> Bool { abs(m.zoom / fitZoom(f) - 1) <= 0.10 }

    func place(_ m: Layout, _ f: Frame) -> Placement {
        let k = coverK(f) * m.zoom
        let dw = W * k, dh = H * k
        let cx = f.fw / 2 + m.ox * f.fw, cy = f.fh / 2 + m.oy * f.fh
        return Placement(k: k, dw: dw, dh: dh, x: cx - dw / 2, y: cy - dh / 2)
    }

    /// A photo larger than the frame can't leave a gap; a smaller one stays inside the frame.
    func clamped(_ m: Layout, _ f: Frame) -> Layout {
        var m = m
        let r = zoomRange(f)
        m.zoom = clamp(m.zoom, r.lowerBound, r.upperBound)
        let p = place(m, f)
        let lx = abs(p.dw - f.fw) / 2 / f.fw
        let ly = abs(p.dh - f.fh) / 2 / f.fh
        m.ox = clamp(m.ox, -lx, lx)
        m.oy = clamp(m.oy, -ly, ly)
        return m
    }

    func hasGap(_ p: Placement, _ f: Frame) -> Bool {
        p.x > 0.5 || p.y > 0.5 || p.x + p.dw < f.fw - 0.5 || p.y + p.dh < f.fh - 0.5
    }

    /// The share of the photo that the frame shows.
    func shownShare(_ p: Placement, _ f: Frame) -> CGFloat {
        let ix = max(0, min(p.x + p.dw, f.fw) - max(p.x, 0))
        let iy = max(0, min(p.y + p.dh, f.fh) - max(p.y, 0))
        return (ix * iy) / (p.dw * p.dh)
    }

    /// Most slides that still keep the whole photo at a ratio Instagram accepts.
    var bestN: Int { Int(clamp((W / H / minAspect + 1e-6).rounded(.down), 2, CGFloat(maxSlides))) }

    /// The slide count a step uses when it didn't fix one: no cropping for Auto,
    /// otherwise the count that shows the most of the photo.
    func autoN(_ shape: Shape) -> Int {
        guard let a = shape.aspect else { return bestN }
        let R = W / H
        var best = 2, bestShown: CGFloat = -1
        for n in 2...maxSlides {
            let F = CGFloat(n) * a
            let shown = min(F, R) / max(F, R)
            if shown > bestShown + 1e-9 { best = n; bestShown = shown }
        }
        return best
    }

    /// The layout a step gives this photo.
    func resolve(_ step: Step) -> Layout {
        var m = Layout(n: step.n ?? autoN(step.shape), shape: step.shape, zoom: 1, ox: step.ox, oy: step.oy, nPicked: step.n != nil)
        let f = frame(m, outW: step.outW)
        m.zoom = step.zoomContain ? step.zoom * containK(f) / coverK(f) : step.zoom
        return clamped(m, f)
    }

    /// Where the photo sits in the 1080 × 1920 Drift frame at time t.
    func driftPlace(_ r: DriftSettings, t: Double) -> Placement {
        var e = r.dur > 0 ? clamp(t / r.dur, 0, 1) : 0
        if r.ease { e = 0.5 - 0.5 * cos(Double.pi * e) }
        let z = CGFloat(r.z0 + (r.z1 - r.z0) * e)
        let pos = CGFloat(r.p0 + (r.p1 - r.p0) * e)
        let k = max(driftSize.width / W, driftSize.height / H) * z
        let dw = W * k, dh = H * k
        return Placement(k: k, dw: dw, dh: dh, x: (driftSize.width - dw) * pos, y: (driftSize.height - dh) * CGFloat(r.v))
    }
}

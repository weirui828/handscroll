import SwiftUI
import PhotosUI

/// Where the editor starts when it adjusts one batch photo for one step.
struct FixContext: Identifiable {
    let id = UUID()
    let photoID: Int
    let step: Step
    let image: UIImage
    let base: String
    let existing: Override?
}

@MainActor
@Observable
final class EditorModel {
    var photo: UIImage?
    var baseName = "photo"
    /// The picker item the photo came from, so Batch can include it.
    private(set) var sourceItem: PhotosPickerItem?
    var mode = Mode.split { didSet { stopDrift(); rebuildPreview() } }
    var layouts: [Mode: Layout] = [:]
    var look = Look() { didSet { rebuildPreview() } }
    var outW: CGFloat = 1080
    var drift = DriftSettings() { didSet { rebuildPreview() } }
    var driftT: Double = 0 { didSet { rebuildPreview() } }
    var playing = false
    var preview: UIImage?
    var status: String?
    var busy = false
    var progress: String?

    private var small: UIImage?
    private var blurCache: [String: UIImage] = [:]
    private let previewPanelWidth: CGFloat = 540

    init() {}

    /// An editor for one batch photo, starting from a step (and any earlier adjustment).
    init(fix: FixContext) {
        setPhoto(fix.image, base: fix.base)
        let geo = Geometry(W: fix.image.size.width, H: fix.image.size.height)
        mode = fix.step.type == .drift ? .drift : .split
        outW = fix.step.outW
        if fix.step.type == .drift {
            drift = fix.existing?.drift ?? fix.step.drift
        } else {
            layouts[.split] = fix.existing?.layout ?? geo.resolve(fix.step)
            look = fix.existing?.look ?? fix.step.look
        }
        rebuildPreview()
    }

    var geo: Geometry? { photo.map { Geometry(W: $0.size.width, H: $0.size.height) } }

    var layout: Layout {
        get { layouts[mode] ?? Layout() }
        set { layouts[mode] = newValue }
    }

    var currentFrame: Frame? { geo.map { $0.frame(layout, outW: previewPanelWidth) } }

    // MARK: Loading

    func load(_ item: PhotosPickerItem) async {
        status = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = await Task.detached(priority: .userInitiated, operation: { Renderer.decode(data) }).value else {
            status = "This photo could not be opened. Try a JPEG or PNG."
            return
        }
        sourceItem = item
        setPhoto(img, base: "photo")
        reset()
    }

    private func setPhoto(_ img: UIImage, base: String) {
        photo = img
        small = Renderer.downscaled(img, side: 2400)
        baseName = base
        blurCache = [:]
    }

#if DEBUG
    /// Loads the bundled sample photo, so the editor can be opened without the picker.
    func loadDemo(named name: String = "demo") {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let img = Renderer.decode(data) else { return }
        sourceItem = nil
        setPhoto(img, base: name)
        reset()
    }
#endif

    // MARK: Layout

    func reset() {
        guard let geo else { return }
        stopDrift()
        driftT = 0
        drift = DriftSettings()
        layouts[.split] = Layout(n: geo.bestN, shape: .auto)
        rebuildPreview()
    }

    func setShape(_ s: Shape) {
        var l = layout
        let oldFit = geo.map { $0.fitZoom($0.frame(l, outW: previewPanelWidth)) }
        let fitScale = oldFit.map { l.zoom / $0 }
        l.shape = s
        l.ox = 0; l.oy = 0
        if l.zoom < 1, let geo, let fitScale {
            l.zoom = fitScale * geo.fitZoom(geo.frame(l, outW: previewPanelWidth))
        }
        layouts[mode] = l
        clampLayout()
    }

    /// True when the photo does not fill the frame, so the fill settings matter.
    var leavesGap: Bool {
        guard let geo, let f = currentFrame else { return false }
        return geo.hasGap(geo.place(layout, f), f)
    }

    /// One output image, or two through five carousel slides. One image starts with the
    /// whole photo fitted; going back to slides fills the frame again.
    func setCount(_ n: Int) {
        var l = layout
        let old = l.n
        l.n = min(maxSlides, max(1, n))
        l.nPicked = true
        if l.n != old, let geo {
            if l.n == 1 {
                l.ox = 0; l.oy = 0
                l.zoom = geo.fitZoom(geo.frame(l, outW: previewPanelWidth))
            } else if old == 1, l.zoom < 1 {
                l.ox = 0; l.oy = 0
                l.zoom = 1
            }
        }
        layouts[mode] = l
        clampLayout()
    }

    func setZoom(_ z: CGFloat) {
        var l = layout
        l.zoom = z
        layouts[mode] = l
        clampLayout()
    }

    /// A small magnetic stop at the zoom that shows the whole photo.
    var isNearFit: Bool {
        guard mode != .drift, let geo, let f = currentFrame else { return false }
        return geo.isNearFit(layout, f)
    }

    @discardableResult
    func snapToFitIfClose() -> Bool {
        guard isNearFit, let geo, let f = currentFrame else { return false }
        var l = layout
        l.zoom = geo.fitZoom(f)
        l.ox = 0
        l.oy = 0
        layouts[mode] = l
        clampLayout()
        return true
    }

    /// Moves by a fraction of the frame.
    func pan(dx: CGFloat, dy: CGFloat, from start: Layout) {
        var l = start
        l.ox += dx; l.oy += dy
        layouts[mode] = l
        clampLayout()
    }

    /// Double-tap: one image switches between the whole photo and a crop centred on the
    /// tapped spot (`at` is a fraction of the frame); slides just go back to filling.
    /// Returns true when the photo ends up fitted.
    @discardableResult
    func toggleFit(at tap: CGPoint) -> Bool {
        guard let geo, let f = currentFrame, layout.n == 1 else { resetPosition(); return false }
        let fit = geo.fitZoom(f)
        var l = layout
        let toFit = abs(l.zoom / fit - 1) > 0.01
        if toFit {
            l.zoom = fit
            l.ox = 0; l.oy = 0
        } else {
            // the photo point under the finger, then the offset that centres it at zoom 1
            let p = geo.place(l, f)
            let px = clamp((tap.x * f.fw - p.x) / p.k, 0, geo.W)
            let py = clamp((tap.y * f.fh - p.y) / p.k, 0, geo.H)
            let k1 = geo.coverK(f)
            l.zoom = 1
            l.ox = k1 * (geo.W / 2 - px) / f.fw
            l.oy = k1 * (geo.H / 2 - py) / f.fh
        }
        layouts[mode] = l
        clampLayout()
        return toFit
    }

    /// Back to the default framing: the whole photo for one image, filled slides otherwise.
    func resetPosition() {
        var l = layout
        l.ox = 0; l.oy = 0
        if l.n == 1, let geo {
            l.zoom = geo.fitZoom(geo.frame(l, outW: previewPanelWidth))
        } else {
            l.zoom = 1
        }
        layouts[mode] = l
        clampLayout()
    }

    func clampLayout() {
        guard let geo else { return }
        layouts[mode] = geo.clamped(layout, geo.frame(layout, outW: previewPanelWidth))
        rebuildPreview()
    }

    /// What the canvas announces to VoiceOver: slide count, shape, size and how
    /// much of the photo shows.
    var info: String {
        guard let geo, photo != nil else { return "" }
        if mode == .drift {
            return "\(Int(driftSize.width)) × \(Int(driftSize.height)) px · \(driftFPS) fps · no sound"
        }
        let f = geo.frame(layout, outW: outW)
        let l = geo.clamped(layout, f)
        let share = Int((geo.shownShare(geo.place(l, f), f) * 100).rounded())
        let count = f.n > 1 ? "\(f.n) slides · " : ""
        return "\(count)\(ratioLabel(f.a)) · \(Int(f.pw)) × \(Int(f.ph)) px · \(share)% of the photo shows"
    }

    /// The output sizes on offer, with the height that the current shape gives them.
    var sizeChoices: [(width: Int, height: Int)] {
        guard let geo, photo != nil, mode != .drift else { return [] }
        let a = geo.panelAspect(layout)
        return [1080, 1440, 2160].map { w in (w, Int((CGFloat(w) / a).rounded())) }
    }

    /// The one line under the photo. The slide count, shape and share are already on screen
    /// in the chips, so this only states the output size.
    var sizeText: String {
        guard let geo, photo != nil else { return "" }
        if mode == .drift { return "\(Int(driftSize.width)) × \(Int(driftSize.height)) px · \(driftFPS) fps" }
        let f = geo.frame(layout, outW: outW)
        return "\(Int(f.pw)) × \(Int(f.ph)) px"
    }

    /// Instagram's app accepts down to 3:4; schedulers stop at 4:5.
    var tallWarning: Bool {
        guard let geo, mode != .drift else { return false }
        return geo.panelAspect(layout) < safeAspect - 0.006
    }

    // MARK: Preview

    private func blur(for f: Frame) -> UIImage? {
        guard let small else { return nil }
        let key = String(format: "%.4f", f.fw / f.fh)
        if let b = blurCache[key] { return b }
        let b = Renderer.blurred(small, size: CGSize(width: f.fw, height: f.fh))
        if let b { blurCache[key] = b }
        return b
    }

    func rebuildPreview() {
        guard let small, let geo else { preview = nil; return }
        if mode == .drift {
            preview = Renderer.driftFrame(photo: small, geo: geo, drift: drift, t: driftT, scale: 0.5)
            return
        }
        let f = geo.frame(layout, outW: previewPanelWidth)
        preview = Renderer.draw(photo: small, geo: geo, layout: layout, frame: f, look: look,
                                blur: look.fill == .blur ? blur(for: f) : nil, panel: nil)
    }

    // MARK: Drift playback

    func stopDrift() { playing = false }

    func togglePlay() {
        if playing { playing = false; return }
        playing = true
        if driftT >= drift.dur - 0.01 { driftT = 0 }
        let t0 = Date().addingTimeInterval(-driftT)
        Task {
            while playing {
                let t = Date().timeIntervalSince(t0)
                if t >= drift.dur { driftT = drift.dur; playing = false; break }
                driftT = t
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    // MARK: Steps

    func captureStep() -> Step? {
        guard let geo else { return nil }
        if mode == .drift {
            return Step(type: .drift, drift: drift)
        }
        let f = geo.frame(layout, outW: outW)
        let m = geo.clamped(layout, f)
        // Zoomed out past filling the frame, the zoom is kept relative to the whole-photo
        // fit, so a fitted photo stays fitted on photos of another shape.
        let contain = m.zoom < 1
        let zoom = contain ? m.zoom / geo.fitZoom(f) : m.zoom
        return Step(type: .split, shape: m.shape, n: m.nPicked ? m.n : nil,
                    zoom: (zoom * 1e4).rounded() / 1e4, zoomContain: contain,
                    ox: (m.ox * 1e4).rounded() / 1e4, oy: (m.oy * 1e4).rounded() / 1e4,
                    look: look, outW: outW)
    }

    func currentOverride() -> Override {
        mode == .drift ? Override(drift: drift) : Override(layout: layout, look: look)
    }

    // MARK: Export

    func exportFiles() async -> [URL] {
        guard let photo else { return [] }
        busy = true
        defer { busy = false; progress = nil }
        stopDrift()
        let dir = Exporter.newFolder()
        let base = baseName
        if mode == .drift {
            do {
                let r = drift
                let url = try await Task.detached(priority: .userInitiated) {
                    try await Exporter.drift(photo: photo, drift: r, name: "\(base)_video", dir: dir) { x in
                        Task { @MainActor in self.progress = "Rendering \(Int(x * 100))%…" }
                    }
                }.value
                return [url]
            } catch {
                status = error.localizedDescription
                return []
            }
        }
        let (l, lk, w) = (layout, look, outW)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try await Exporter.images(photo: photo, layout: l, look: lk, outW: w, prefix: base, dir: dir) { i, n in
                    Task { @MainActor in self.progress = n > 1 ? "Rendering \(i) of \(n)…" : "Rendering…" }
                }
            }.value
        } catch {
            status = "Could not export: \(error.localizedDescription)"
            return []
        }
    }

    func saveToPhotos(_ urls: [URL]) async {
        busy = true
        defer { busy = false }
        status = await PhotoNames.save(urls)
    }
}

enum PhotoNames {
    /// Adds images and videos to Photos. Returns a message for the user.
    static func save(_ urls: [URL]) async -> String {
        guard !urls.isEmpty else { return "No files are ready to save." }
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            return "An exported file is missing. Export again and retry saving."
        }
        var access = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if access == .notDetermined {
            access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard access == .authorized || access == .limited else {
            return "Photos access is off. Allow Handscroll to add photos in Settings, then try again."
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for u in urls {
                    if u.pathExtension.lowercased() == "mp4" {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u)
                    } else {
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: u)
                    }
                }
            }
            return "Saved \(urls.count) \(urls.count == 1 ? "file" : "files") to Photos."
        } catch {
            return "Could not save to Photos: \(error.localizedDescription)"
        }
    }
}

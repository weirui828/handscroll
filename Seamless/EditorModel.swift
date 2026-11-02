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
    var mode = Mode.carousel { didSet { stopReel(); rebuildPreview() } }
    var layouts: [Mode: Layout] = [:]
    var look = Look() { didSet { rebuildPreview() } }
    var outW: CGFloat = 1080
    var reel = ReelSettings() { didSet { rebuildPreview() } }
    var reelT: Double = 0 { didSet { rebuildPreview() } }
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
        mode = fix.step.type
        outW = fix.step.outW
        if fix.step.type == .reel {
            reel = fix.existing?.reel ?? fix.step.reel
        } else {
            layouts[fix.step.type] = fix.existing?.layout ?? geo.resolve(fix.step)
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
        setPhoto(img, base: await PhotoNames.originalName(item) ?? "photo")
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
        stopReel()
        reelT = 0
        reel = ReelSettings()
        layouts[.carousel] = Layout(n: geo.bestN, shape: .auto)
        for m in [Mode.fit, .crop] { layouts[m] = Layout(n: 1, shape: .r45) }
        layouts[.fit] = refitted(layouts[.fit]!)
        rebuildPreview()
    }

    /// Fit starts with the whole photo inside the frame.
    private func refitted(_ l: Layout) -> Layout {
        guard let geo else { return l }
        var l = l
        l.zoom = geo.fitZoom(geo.frame(l, outW: previewPanelWidth))
        l.ox = 0; l.oy = 0
        return l
    }

    func setShape(_ s: Shape) {
        var l = layout
        l.shape = s
        l.ox = 0; l.oy = 0
        l.zoom = 1
        layouts[mode] = mode == .fit ? refitted(l) : l
        clampLayout()
    }

    /// True when the photo is shown whole (zoom == fit), so the Fit segment reads as selected.
    var showsWholePhoto: Bool {
        guard let geo, let f = currentFrame else { return false }
        return abs(layout.zoom - geo.fitZoom(f)) < 0.01
    }

    /// True when the photo does not fill the frame, so the fill settings matter.
    var leavesGap: Bool {
        guard let geo, let f = currentFrame else { return false }
        return geo.hasGap(geo.place(layout, f), f)
    }

    func setCount(_ n: Int) {
        var l = layout
        l.n = n
        l.nPicked = true
        layouts[mode] = l
        clampLayout()
    }

    func setZoom(_ z: CGFloat) {
        var l = layout
        l.zoom = z
        layouts[mode] = l
        clampLayout()
    }

    /// Moves by a fraction of the frame.
    func pan(dx: CGFloat, dy: CGFloat, from start: Layout) {
        var l = start
        l.ox += dx; l.oy += dy
        layouts[mode] = l
        clampLayout()
    }

    /// Back to the starting position of the current mode.
    func resetPosition() {
        var l = layout
        l.ox = 0; l.oy = 0; l.zoom = 1
        layouts[mode] = mode == .fit ? refitted(l) : l
        clampLayout()
    }

    func wholePhoto() {
        guard let geo, let f = currentFrame else { return }
        var l = layout
        l.ox = 0; l.oy = 0; l.zoom = geo.fitZoom(f)
        layouts[mode] = l
        clampLayout()
    }

    func fillFrame() {
        var l = layout
        l.ox = 0; l.oy = 0; l.zoom = 1
        layouts[mode] = l
        clampLayout()
    }

    func center() {
        var l = layout
        l.ox = 0; l.oy = 0
        layouts[mode] = l
        clampLayout()
    }

    func clampLayout() {
        guard let geo else { return }
        layouts[mode] = geo.clamped(layout, geo.frame(layout, outW: previewPanelWidth))
        rebuildPreview()
    }

    /// One line under the canvas: slide shape, size and how much of the photo shows.
    var info: String {
        guard let geo, photo != nil else { return "" }
        if mode == .reel {
            return "\(Int(reelSize.width)) × \(Int(reelSize.height)) px · \(reelFPS) fps · no sound"
        }
        let f = geo.frame(layout, outW: outW)
        let l = geo.clamped(layout, f)
        let share = Int((geo.shownShare(geo.place(l, f), f) * 100).rounded())
        let count = f.n > 1 ? "\(f.n) slides · " : ""
        return "\(count)\(ratioLabel(f.a)) · \(Int(f.pw)) × \(Int(f.ph)) px · \(share)% of the photo shows"
    }

    /// The photo's own aspect, which is what the canvas actually shows.
    var photoAspect: CGFloat {
        guard let photo, photo.size.height > 0 else { return 1.5 }
        return photo.size.width / photo.size.height
    }

    /// The output sizes on offer, with the height that the current shape gives them.
    var sizeChoices: [(width: Int, height: Int)] {
        guard let geo, photo != nil, mode != .reel else { return [] }
        let a = geo.panelAspect(layout)
        return [1080, 1440, 2160].map { w in (w, Int((CGFloat(w) / a).rounded())) }
    }

    /// The one line under the photo. The slide count, shape and share are already on screen
    /// in the chips, so this only states the output size.
    var sizeText: String {
        guard let geo, photo != nil else { return "" }
        if mode == .reel { return "\(Int(reelSize.width)) × \(Int(reelSize.height)) px · \(reelFPS) fps" }
        let f = geo.frame(layout, outW: outW)
        return "\(Int(f.pw)) × \(Int(f.ph)) px"
    }

    /// Instagram's app accepts down to 3:4; schedulers stop at 4:5.
    var tallWarning: Bool {
        guard let geo, mode != .reel else { return false }
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
        if mode == .reel {
            preview = Renderer.reelFrame(photo: small, geo: geo, reel: reel, t: reelT, scale: 0.5)
            return
        }
        let f = geo.frame(layout, outW: previewPanelWidth)
        preview = Renderer.draw(photo: small, geo: geo, layout: layout, frame: f, look: look,
                                blur: look.fill == .blur ? blur(for: f) : nil, panel: nil)
    }

    // MARK: Reel playback

    func stopReel() { playing = false }

    func togglePlay() {
        if playing { playing = false; return }
        playing = true
        if reelT >= reel.dur - 0.01 { reelT = 0 }
        let t0 = Date().addingTimeInterval(-reelT)
        Task {
            while playing {
                let t = Date().timeIntervalSince(t0)
                if t >= reel.dur { reelT = reel.dur; playing = false; break }
                reelT = t
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    // MARK: Steps

    func captureStep() -> Step? {
        guard let geo else { return nil }
        if mode == .reel {
            return Step(type: .reel, reel: reel)
        }
        let f = geo.frame(layout, outW: outW)
        let m = geo.clamped(layout, f)
        let contain = geo.fitZoom(f)
        let isFit = mode == .fit
        return Step(type: mode, shape: m.shape, n: mode == .carousel ? (m.nPicked ? m.n : nil) : 1,
                    zoom: ((isFit ? m.zoom / contain : m.zoom) * 1e4).rounded() / 1e4, zoomContain: isFit,
                    ox: (m.ox * 1e4).rounded() / 1e4, oy: (m.oy * 1e4).rounded() / 1e4,
                    look: look, outW: outW)
    }

    func apply(_ step: Step) {
        guard let geo else { return }
        stopReel()
        if step.type == .reel {
            reel = step.reel
            reelT = 0
        } else {
            layouts[step.type] = geo.resolve(step)
            look = step.look
            outW = step.outW
        }
        mode = step.type
        rebuildPreview()
    }

    func currentOverride() -> Override {
        mode == .reel ? Override(reel: reel) : Override(layout: layout, look: look)
    }

    // MARK: Export

    func exportFiles() async -> [URL] {
        guard let photo else { return [] }
        busy = true
        defer { busy = false; progress = nil }
        stopReel()
        let dir = Exporter.newFolder()
        let base = baseName
        if mode == .reel {
            do {
                let r = reel
                let url = try await Task.detached(priority: .userInitiated) {
                    try await Exporter.reel(photo: photo, reel: r, name: "\(base)_reel", dir: dir) { x in
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
    /// The file name the photo had when it was taken, without its extension.
    static func originalName(_ item: PhotosPickerItem) async -> String? {
        guard let id = item.itemIdentifier else { return nil }
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard access == .authorized || access == .limited else { return nil }
        let r = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = r.firstObject, let name = PHAssetResource.assetResources(for: asset).first?.originalFilename else { return nil }
        return (name as NSString).deletingPathExtension
    }

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
            return "Photos access is off. Allow Seamless to add photos in Settings, then try again."
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

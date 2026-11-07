import SwiftUI
import PhotosUI

struct BatchPhoto: Identifiable {
    let id: Int
    let item: PhotosPickerItem
    let base: String
    var thumb: UIImage?
    var failed = false
    var overrides: [String: Override] = [:]
}

@MainActor
@Observable
final class BatchModel {
    private static let storeKey = "seamless.workflow.v1"

    var steps: [Step] = [] { didSet { saveSteps(); cells = [:] } }
    var photos: [BatchPhoto] = [] { didSet { cells = [:] } }
    var busy = false
    var progress: String?
    var status: String?
    var warning: String?
    var results: [URL] = []

    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var cells: [String: UIImage] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode([Step].self, from: data) {
            steps = Array(saved.prefix(maxSteps))
        }
    }

    private func saveSteps() {
        if let data = try? JSONEncoder().encode(steps) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }

    // MARK: Steps

    /// Adds a step unless it repeats an earlier one. Returns a note for the user.
    func add(_ step: Step) -> String {
        if steps.count >= maxSteps { return "A batch holds up to \(maxSteps) steps." }
        if let dup = steps.firstIndex(where: { $0.sameAs(step) }) { return "Same as step \(dup + 1), so nothing was added." }
        steps.append(step)
        return "Added as step \(steps.count). Change any setting to add another."
    }

    func remove(_ step: Step) {
        steps.removeAll { $0.id == step.id }
        for i in photos.indices { photos[i].overrides[step.id] = nil }
        results = []
    }

    // MARK: Photos

    func add(_ items: [PhotosPickerItem]) async {
        let room = maxPhotos - photos.count
        warning = items.count > room ? "A batch holds up to \(maxPhotos) photos, so \(items.count - room) were left out." : nil
        var added: [Int] = []
        var taken = Set(photos.map(\.base))
        for item in items.prefix(max(0, room)) {
            var base = "photo"
            let root = base
            var k = 2
            while taken.contains(base) { base = "\(root)-\(k)"; k += 1 }
            taken.insert(base)
            photos.append(BatchPhoto(id: nextID, item: item, base: base))
            added.append(nextID)
            nextID += 1
        }
        results = []
        for id in added {
            guard let item = photos.first(where: { $0.id == id })?.item else { continue }
            let thumb = await Self.load(item, cap: thumbPixels)
            if let i = photos.firstIndex(where: { $0.id == id }) {
                photos[i].thumb = thumb
                photos[i].failed = thumb == nil
            }
        }
    }

    /// True when this picker item is already in the batch.
    func contains(_ item: PhotosPickerItem) -> Bool {
        photos.contains { $0.item.itemIdentifier == item.itemIdentifier }
    }

    func removePhoto(_ id: Int) {
        photos.removeAll { $0.id == id }
        results = []
    }

    static func load(_ item: PhotosPickerItem, cap: CGFloat) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await Task.detached(priority: .userInitiated) { Renderer.decode(data, cap: cap) }.value
    }

    // MARK: Per-photo settings

    func setOverride(_ o: Override?, photo: Int, step: String) {
        guard let i = photos.firstIndex(where: { $0.id == photo }) else { return }
        photos[i].overrides[step] = o
        results = []
        cells = [:]
    }

    func fixContext(photo id: Int, step: Step) async -> FixContext? {
        guard let p = photos.first(where: { $0.id == id }),
              let img = await Self.load(p.item, cap: maxPixels) else { return nil }
        return FixContext(photoID: id, step: step, image: img, base: p.base, existing: p.overrides[step.id])
    }

    /// What to render for one photo and step, including any per-photo adjustment.
    struct Spec {
        var layout: Layout?
        var look: Look
        var drift: DriftSettings
    }

    func spec(_ photo: BatchPhoto, _ img: UIImage, _ step: Step) -> Spec {
        let o = photo.overrides[step.id]
        if step.type == .drift { return Spec(layout: nil, look: step.look, drift: o?.drift ?? step.drift) }
        let geo = Geometry(W: img.size.width, H: img.size.height)
        return Spec(layout: o?.layout ?? geo.resolve(step), look: o?.look ?? step.look, drift: step.drift)
    }

    /// A small preview of one result.
    func cell(_ photo: BatchPhoto, _ step: Step) -> UIImage? {
        guard let thumb = photo.thumb else { return nil }
        let key = "\(photo.id)/\(step.id)"
        if let c = cells[key] { return c }
        let s = spec(photo, thumb, step)
        let geo = Geometry(W: thumb.size.width, H: thumb.size.height)
        let img: UIImage
        if step.type == .drift {
            img = Renderer.driftFrame(photo: thumb, geo: geo, drift: s.drift, t: s.drift.dur / 2, scale: 0.1)
        } else if let layout = s.layout {
            let f = geo.frame(layout, outW: 140)
            let blur = s.look.fill == .blur ? Renderer.blurred(thumb, size: CGSize(width: f.fw, height: f.fh)) : nil
            img = Renderer.draw(photo: thumb, geo: geo, layout: geo.clamped(layout, f), frame: f, look: s.look, blur: blur, panel: nil)
        } else { return nil }
        cells[key] = img
        return img
    }

    // MARK: Estimate

    var estimate: (files: Int, bytes: Double, secs: Double) {
        var files = 0, bytes = 0.0, secs = 0.0
        for p in photos {
            guard let t = p.thumb else { continue }
            secs += 0.4
            for step in steps {
                let s = spec(p, t, step)
                if step.type == .drift {
                    files += 1
                    bytes += s.drift.dur * 1.5e6
                    secs += s.drift.dur * 0.4
                } else if let l = s.layout {
                    let f = Geometry(W: t.size.width, H: t.size.height).frame(l, outW: step.outW)
                    files += f.n
                    bytes += Double(f.n) * Double(f.pw * f.ph) * 0.25
                    secs += Double(f.n) * 0.15
                }
            }
        }
        return (files, bytes, secs)
    }

    var estimateText: String {
        let e = estimate
        guard e.files > 0 else { return "" }
        let size = e.bytes > 1e6 ? String(format: "%.1f MB", e.bytes / 1e6) : "\(Int(e.bytes / 1e3)) KB"
        let time = e.secs < 90 ? "\(max(5, Int((e.secs / 5).rounded()) * 5)) s" : "\(Int((e.secs / 60).rounded())) min"
        return "≈ \(e.files) files · ≈ \(size) · about \(time)"
    }

    var canRun: Bool { !busy && !steps.isEmpty && photos.contains { $0.thumb != nil } }

    // MARK: Run

    /// One photo at a time at full size, released before the next, so memory stays flat.
    func run() async {
        guard canRun else { return }
        busy = true
        results = []
        status = nil
        let total = estimate.files
        var done = 0
        var out: [URL] = []
        let dir = Exporter.newFolder()
        defer { busy = false; progress = nil }
        do {
            for p in photos where p.thumb != nil {
                progress = "\(min(done + 1, total)) of \(total)…"
                guard let full = await Self.load(p.item, cap: maxPixels) else { continue }
                for (si, step) in steps.enumerated() {
                    let s = spec(p, full, step)
                    let prefix = "\(p.base)_\(si + 1)-\(step.type.rawValue.lowercased())"
                    if step.type == .drift {
                        let r = s.drift, base = p.base, count = min(done + 1, total), all = total
                        let url = try await Task.detached(priority: .userInitiated) {
                            try await Exporter.drift(photo: full, drift: r, name: "\(base)_\(si + 1)-video", dir: dir) { x in
                                Task { @MainActor in self.progress = "\(count) of \(all) · \(Int(x * 100))%" }
                            }
                        }.value
                        out.append(url)
                        done += 1
                    } else if let layout = s.layout {
                        let look = s.look, w = step.outW
                        let urls = try await Task.detached(priority: .userInitiated) {
                            try await Exporter.images(photo: full, layout: layout, look: look, outW: w, prefix: prefix, dir: dir)
                        }.value
                        out += urls
                        done += urls.count
                    }
                    progress = "\(min(done + 1, total)) of \(total)…"
                }
            }
            results = out
            status = out.isEmpty ? "Nothing was made." : "Made \(out.count) files."
        } catch {
            status = error.localizedDescription
        }
    }

    func saveToPhotos() async {
        busy = true
        defer { busy = false }
        status = await PhotoNames.save(results)
    }
}

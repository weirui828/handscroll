import UIKit

/// Writes finished files into a temporary folder. Names: photo_01.jpg, photo_02.jpg…
enum Exporter {
    static func newFolder() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("slides-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func images(photo: UIImage, layout: Layout, look: Look, outW: CGFloat, prefix: String, dir: URL,
                       onFile: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [URL] {
        let geo = Geometry(W: photo.size.width, H: photo.size.height)
        let f = geo.frame(layout, outW: outW)
        let l = geo.clamped(layout, f)
        let blur = look.fill == .blur ? Renderer.blurred(photo, size: CGSize(width: f.fw, height: f.fh)) : nil
        let shown = geo.place(l, f)
        let src = Renderer.sized(photo, covering: CGSize(width: shown.dw, height: shown.dh))
        var urls: [URL] = []
        for i in 0..<f.n {
            let img = Renderer.draw(photo: src, geo: geo, layout: l, frame: f, look: look, blur: blur, panel: i)
            guard let data = img.jpegData(compressionQuality: Renderer.jpegQuality) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let url = dir.appendingPathComponent(String(format: "%@_%02d.jpg", prefix, i + 1))
            try data.write(to: url, options: .atomic)
            urls.append(url)
            onFile?(i + 1, f.n)
            await Task.yield()
        }
        return urls
    }

    static func reel(photo: UIImage, reel: ReelSettings, name: String, dir: URL,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let url = dir.appendingPathComponent("\(name).mp4")
        try await ReelEncoder.render(photo: photo, reel: reel, to: url, progress: progress)
        return url
    }
}

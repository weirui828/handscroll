import UIKit
import AVFoundation

struct ReelError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Frame by frame with AVAssetWriter: faster than real time and no dropped frames.
enum ReelEncoder {
    static func render(photo: UIImage, reel: ReelSettings, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let src = Renderer.downscaled(photo, side: 4000)
        let geo = Geometry(W: src.size.width, H: src.size.height)
        let w = Int(reelSize.width), h = Int(reelSize.height)

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 16_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: reelFPS,
            ],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ])
        guard writer.canAdd(input) else { throw ReelError(message: "This device can't make the video.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ReelError(message: "The video could not start.") }
        writer.startSession(atSourceTime: .zero)

        let frames = max(2, Int((reel.dur * Double(reelFPS)).rounded()))
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? ReelError(message: "The video failed.") }
                try await Task.sleep(for: .milliseconds(3))
            }
            guard let pool = adaptor.pixelBufferPool else { throw ReelError(message: "The video buffer is missing.") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pb = buffer else { throw ReelError(message: "The device ran out of memory.") }

            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                let p = geo.reelPlace(reel, t: Double(i) / Double(frames - 1) * reel.dur)
                ctx.translateBy(x: 0, y: CGFloat(h))
                ctx.scaleBy(x: 1, y: -1)
                ctx.interpolationQuality = .high
                UIGraphicsPushContext(ctx)
                src.draw(in: CGRect(x: p.x, y: p.y, width: p.dw, height: p.dh))
                UIGraphicsPopContext()
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            adaptor.append(pb, withPresentationTime: CMTime(value: Int64(i), timescale: Int32(reelFPS)))
            if i % 10 == 0 { progress(Double(i) / Double(frames)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ReelError(message: "The video could not be saved.") }
    }
}

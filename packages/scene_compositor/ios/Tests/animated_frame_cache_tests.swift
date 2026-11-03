import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// Compiled by check_animated_frame_cache.py next to the extracted production
/// frame copy and cache. Replays the catalog GIF overlays the way a layer
/// does: every frame that comes back must be the frame a fresh decode gives,
/// at any cadence, for each layer on its own and within the byte budget.
@main
struct AnimatedFrameCacheTests {
    /// The options `decodeAnimatedFrame` uses; the runner checks they match.
    static let frameOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1440,
        kCGImageSourceShouldCacheImmediately: false,
    ]

    struct Overlay {
        let name: String
        let source: CGImageSource
        let count: Int

        init(path: String) {
            guard
                let source = CGImageSourceCreateWithURL(
                    URL(fileURLWithPath: path) as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                ),
                CGImageSourceGetCount(source) > 0
            else { fatalError("Unreadable GIF: \(path)") }
            name = (path as NSString).lastPathComponent
            self.source = source
            count = min(CGImageSourceGetCount(source), 600)
        }

        func decode(_ index: Int) -> CGImage {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(
                source, index, AnimatedFrameCacheTests.frameOptions as CFDictionary
            ) else { fatalError("\(name): frame \(index) did not decode") }
            return frame
        }
    }

    static func expectIdentical(_ actual: CGImage, _ expected: CGImage, _ label: String) {
        precondition(actual.width == expected.width, "\(label): width")
        precondition(actual.height == expected.height, "\(label): height")
        precondition(actual.bitsPerComponent == expected.bitsPerComponent, "\(label): bitsPerComponent")
        precondition(actual.bitsPerPixel == expected.bitsPerPixel, "\(label): bitsPerPixel")
        precondition(actual.bytesPerRow == expected.bytesPerRow, "\(label): bytesPerRow")
        precondition(actual.bitmapInfo == expected.bitmapInfo, "\(label): bitmapInfo")
        precondition(actual.shouldInterpolate == expected.shouldInterpolate, "\(label): interpolation")
        precondition(actual.renderingIntent == expected.renderingIntent, "\(label): rendering intent")
        guard let space = actual.colorSpace, let expectedSpace = expected.colorSpace,
              CFEqual(space, expectedSpace)
        else { preconditionFailure("\(label): color space") }
        guard let bytes = actual.dataProvider?.data as Data?,
              let expectedBytes = expected.dataProvider?.data as Data?
        else { preconditionFailure("\(label): missing pixel data") }
        precondition(bytes == expectedBytes, "\(label): pixels differ")
    }

    /// Every frame survives its copy exactly, and the copy holds only its own
    /// bytes: a buffer kept at the decoded size would make the budget a lie.
    static func checkEveryFrame(_ overlay: Overlay) -> (decoded: Int, compressed: Int) {
        var decoded = 0, compressed = 0
        for index in 0..<overlay.count {
            autoreleasepool {
                let frame = overlay.decode(index)
                guard let copy = SceneSurfaceCompressedAnimatedFrame(frame) else {
                    preconditionFailure("\(overlay.name) #\(index): no copy")
                }
                let allocated = copy.compressed.withUnsafeBytes {
                    malloc_size($0.baseAddress!)
                }
                precondition(
                    allocated > 0 && allocated <= copy.compressed.count + 16_384,
                    "\(overlay.name) #\(index): copy holds \(allocated) bytes for \(copy.compressed.count)"
                )
                guard let restored = copy.makeImage() else {
                    preconditionFailure("\(overlay.name) #\(index): copy did not rebuild")
                }
                expectIdentical(restored, frame, "\(overlay.name) #\(index)")
                decoded += copy.decodedLength
                compressed += copy.compressed.count
            }
        }
        return (decoded, compressed)
    }

    /// One layer at a given cadence: `step` frames advance per tick, as when
    /// the thermal brake lowers the frame rate, over `loops` loops.
    static func replay(
        _ overlay: Overlay,
        step: Int,
        loops: Int,
        into cache: inout SceneSurfaceCompressedAnimatedFrameCache
    ) -> Int {
        var hits = 0
        var visited = Set<Int>()
        for tick in 0..<(loops * overlay.count / step) {
            let index = (tick * step) % overlay.count
            autoreleasepool {
                if let copy = cache.image(at: index) {
                    precondition(visited.contains(index), "\(overlay.name) #\(index): replayed a frame never decoded")
                    hits += 1
                    expectIdentical(copy, overlay.decode(index), "\(overlay.name) step \(step) #\(index)")
                } else {
                    cache.remember(overlay.decode(index), at: index)
                }
            }
            visited.insert(index)
        }
        return hits
    }

    static func checkCadences(_ overlay: Overlay) {
        for step in [1, 2, 4] {
            var cache = SceneSurfaceCompressedAnimatedFrameCache()
            let ticks = 2 * overlay.count / step
            let distinct = Set((0..<ticks).map { ($0 * step) % overlay.count }).count
            let hits = replay(overlay, step: step, loops: 2, into: &cache)
            // The catalog fits the budget, so every revisit is a replay.
            precondition(!cache.full && cache.bytes <= cache.bytesLimit, "\(overlay.name): budget")
            precondition(hits == ticks - distinct, "\(overlay.name) step \(step): \(hits) replays, expected \(ticks - distinct)")
        }
    }

    /// Two layers animate at once; neither sees the other's frames or bytes.
    static func checkTwoLayers(_ first: Overlay, _ second: Overlay) {
        var alone = SceneSurfaceCompressedAnimatedFrameCache()
        _ = replay(first, step: 1, loops: 1, into: &alone)
        var a = SceneSurfaceCompressedAnimatedFrameCache()
        var b = SceneSurfaceCompressedAnimatedFrameCache()
        for index in 0..<max(first.count, second.count) {
            autoreleasepool {
                if index < first.count { a.remember(first.decode(index), at: index) }
                if index < second.count { b.remember(second.decode(index), at: index) }
            }
        }
        precondition(a.bytes == alone.bytes, "layers share a budget")
        for index in [0, min(first.count, second.count) - 1] {
            autoreleasepool {
                expectIdentical(a.image(at: index)!, first.decode(index), "layer A #\(index)")
                expectIdentical(b.image(at: index)!, second.decode(index), "layer B #\(index)")
            }
        }
    }

    /// Past the budget nothing more is kept, kept frames still replay exactly,
    /// and a new source starts with the whole budget again.
    static func checkBudget(_ overlay: Overlay) {
        precondition(overlay.count >= 4, "\(overlay.name): too few frames for the budget check")
        let sizes = (0..<2).map { SceneSurfaceCompressedAnimatedFrame(overlay.decode($0))!.compressed.count }
        var cache = SceneSurfaceCompressedAnimatedFrameCache(bytesLimit: sizes[0] + sizes[1] + 10)
        cache.remember(overlay.decode(0), at: 0)
        cache.remember(overlay.decode(0), at: 0)
        precondition(cache.bytes == sizes[0], "a frame is counted once")
        cache.remember(overlay.decode(1), at: 1)
        precondition(cache.bytes == sizes[0] + sizes[1] && !cache.full, "two frames fit")
        cache.remember(overlay.decode(2), at: 2)
        precondition(cache.full && cache.bytes == sizes[0] + sizes[1], "the third frame does not fit")
        cache.remember(overlay.decode(3), at: 3)
        precondition(cache.bytes == sizes[0] + sizes[1], "nothing is kept once full")
        precondition(cache.image(at: 2) == nil && cache.image(at: 3) == nil, "frames past the budget decode again")
        expectIdentical(cache.image(at: 0)!, overlay.decode(0), "kept frame after the budget")
        cache.removeAll(keepingCapacity: true)
        precondition(cache.bytes == 0 && !cache.full && cache.image(at: 0) == nil, "reset")
        cache.remember(overlay.decode(0), at: 0)
        precondition(cache.bytes == sizes[0], "a new source gets the budget again")
    }

    static func main() {
        let overlays = CommandLine.arguments.dropFirst().map(Overlay.init(path:))
        precondition(overlays.count >= 2, "Pass at least two GIF overlays")
        let mb = { (bytes: Int) in String(format: "%.2f MB", Double(bytes) / 1_048_576) }
        var frames = 0
        for overlay in overlays {
            let sizes = checkEveryFrame(overlay)
            checkCadences(overlay)
            frames += overlay.count
            let sample = overlay.decode(0)
            print("\(overlay.name): \(overlay.count) frames \(sample.width)x\(sample.height), "
                + "decoded \(mb(sizes.decoded)) -> LZ4 \(mb(sizes.compressed)) "
                + "(budget \(mb(sceneSurfaceAnimatedImageCompressedCacheBytesLimit)) per layer)")
        }
        checkTwoLayers(overlays[0], overlays[1])
        checkBudget(overlays.first { $0.count >= 4 }!)
        print("Animated frame cache: \(frames) frames of \(overlays.count) GIFs identical; "
            + "cadences 1/2/4, two layers and budget checked")
    }
}

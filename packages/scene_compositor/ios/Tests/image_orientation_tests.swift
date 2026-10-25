import Foundation
import CoreGraphics
import CoreImage
import ImageIO

@main
struct ImageOrientationTests {
    static let context = CIContext(options: [.useSoftwareRenderer: true])

    static func pixels(_ image: CIImage) -> [UInt8] {
        let bounds = image.extent
        let width = Int(bounds.width), height = Int(bounds.height)
        var result = [UInt8](repeating: 0, count: width * height * 4)
        result.withUnsafeMutableBytes { bytes in
            context.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 4,
                           bounds: bounds, format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        return result
    }

    static func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX, y: -image.extent.minY))
    }

    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let bitmap = CGContext(data: nil, width: 8, height: 12, bitsPerComponent: 8,
                               bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        bitmap.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
        let original = bitmap.makeImage()!
        for (orientation, transform) in [(1, CGImagePropertyOrientation.up), (3, .down), (6, .right)] {
            let url = directory.appendingPathComponent("exif-\(orientation).jpg")
            let writer = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(writer, original, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            precondition(CGImageDestinationFinalize(writer))
            let legacy = CIImage(contentsOf: url)!.oriented(.up)
            let off = sceneSurfaceLoadImage(path: url.path, applyImageOrientation: false)!
            let on = sceneSurfaceLoadImage(path: url.path, applyImageOrientation: true)!
            let expected = normalized(legacy.oriented(transform))
            precondition(off.extent == legacy.extent && pixels(off) == pixels(legacy),
                         "OFF changed historical source pixels for EXIF \(orientation)")
            precondition(on.extent.origin == .zero && on.extent.size == expected.extent.size,
                         "ON returned a wrong logical extent for EXIF \(orientation)")
            precondition(pixels(on) == pixels(expected),
                         "ON pixels disagree with EXIF \(orientation)")
            if orientation != 1 { precondition(pixels(off) != pixels(on)) }
            let definition: [String: Any] = ["id": "image", "role": "background", "sourceKind": "image",
                "path": url.path, "opacity": 1, "transform": ["width": 1, "height": 1]]
            let identity = SceneSurfaceLayerSourceIdentity.key(definition)!
            var oriented = definition
            oriented["applyImageOrientation"] = true
            precondition(SceneSurfaceLayerSourceIdentity.key(oriented) != identity,
                         "Orientation switch reused a legacy source")
            var presentation = oriented
            presentation["opacity"] = 0.5
            precondition(SceneSurfaceLayerSourceIdentity.key(presentation) ==
                         SceneSurfaceLayerSourceIdentity.key(oriented),
                         "Presentation-only change lost oriented-source reuse")
            print("EXIF \(orientation): OFF legacy identical; ON \(Int(on.extent.width))x\(Int(on.extent.height)), pixels and reuse identity correct")
        }
    }
}

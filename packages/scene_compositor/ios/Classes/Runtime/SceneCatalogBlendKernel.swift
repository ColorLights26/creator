import CoreGraphics
import CoreImage

/// Canvas source-over is authored in the source's encoded color space. Keep
/// that operation local to these procedural layers; the scene's working color
/// space and the existing media composition route remain unchanged.
enum SceneCatalogBlendKernel {
  static func sourceOver(
    _ source: CIImage,
    background: CIImage,
    target: CGRect,
    colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
  ) throws -> CIImage {
    try sourceOverSequence([source], background: background,
      target: target, colorSpace: colorSpace)
  }

  /// Adjacent authored-color layers stay in their shared blend space. Decode
  /// once at the boundary; never reorder across media, other blends or filters.
  static func sourceOverSequence(
    _ sources: [CIImage],
    background: CIImage,
    target: CGRect,
    colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
  ) throws -> CIImage {
    guard !sources.isEmpty else { return background }
    guard var encoded = background.matchedFromWorkingSpace(to: colorSpace) else {
      throw BlendError.colorSpaceConversionFailed
    }
    for source in sources {
      guard let next = source.matchedFromWorkingSpace(to: colorSpace) else {
        throw BlendError.colorSpaceConversionFailed
      }
      encoded = next.composited(over: encoded).cropped(to: target)
    }
    guard let result = encoded.matchedToWorkingSpace(from: colorSpace) else {
      throw BlendError.colorSpaceConversionFailed
    }
    return result.cropped(to: target)
  }

  private enum BlendError: Error { case colorSpaceConversionFailed }
}

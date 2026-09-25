// Impeller analytic blur and circle algorithms:
// Copyright 2013 The Flutter Authors. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// * Neither the name of Google Inc. nor the names of its contributors may be
//   used to endorse or promote products derived from this software without
//   specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

import Foundation
import CoreGraphics
import Metal
import simd

// Only the vector operations used by the installed Neon Club painter are
// represented here. Geometry stays vector data; no CPU bitmap is constructed.
struct SceneCatalogVectorOffset {
  let dx: Double
  let dy: Double
  init(_ dx: Double, _ dy: Double) { self.dx = dx; self.dy = dy }
  static let zero = Self(0, 0)
  var point: CGPoint { CGPoint(x: dx, y: dy) }
  func translate(_ x: Double, _ y: Double) -> Self { Self(dx + x, dy + y) }
  static func + (a: Self, b: Self) -> Self { Self(a.dx + b.dx, a.dy + b.dy) }
  static func * (a: Self, b: Double) -> Self { Self(a.dx * b, a.dy * b) }
  static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self {
    Self(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t)
  }
}
struct SceneCatalogVectorSize {
  let width: Double
  let height: Double
  init(_ width: Double, _ height: Double) { self.width = width; self.height = height }
  var shortestSide: Double { min(width, height) }
  var longestSide: Double { max(width, height) }
}
struct SceneCatalogVectorRect {
  let rect: CGRect
  var left: Double { rect.minX }
  var top: Double { rect.minY }
  var right: Double { rect.maxX }
  var bottom: Double { rect.maxY }
  var width: Double { rect.width }
  var height: Double { rect.height }
  var center: SceneCatalogVectorOffset { .init(rect.midX, rect.midY) }
  static func fromCenter(center: SceneCatalogVectorOffset, width: Double, height: Double) -> Self {
    .init(rect: CGRect(x: center.dx - width / 2, y: center.dy - height / 2, width: width, height: height))
  }
  static func fromCircle(center: SceneCatalogVectorOffset, radius: Double) -> Self {
    fromCenter(center: center, width: radius * 2, height: radius * 2)
  }
  static func fromLTWH(_ left: Double, _ top: Double, _ width: Double, _ height: Double) -> Self {
    .init(rect: CGRect(x: left, y: top, width: width, height: height))
  }
  func deflate(_ amount: Double) -> Self { .init(rect: rect.insetBy(dx: amount, dy: amount)) }
  func inflate(_ amount: Double) -> Self { deflate(-amount) }
}
func & (offset: SceneCatalogVectorOffset, size: SceneCatalogVectorSize) -> SceneCatalogVectorRect {
  .fromLTWH(offset.dx, offset.dy, size.width, size.height)
}
struct SceneCatalogVectorRadius {
  let radius: Double
  static func circular(_ radius: Double) -> Self { .init(radius: radius) }
}
struct SceneCatalogVectorRRect {
  let outerRect: SceneCatalogVectorRect
  let radius: Double
  static func fromRectAndRadius(_ rect: SceneCatalogVectorRect, _ radius: SceneCatalogVectorRadius) -> Self {
    .init(outerRect: rect, radius: min(radius.radius, min(rect.width, rect.height) / 2))
  }
}
final class SceneCatalogVectorPath {
  let path = CGMutablePath()
  func moveTo(_ x: Double, _ y: Double) { path.move(to: CGPoint(x: x, y: y)) }
  func lineTo(_ x: Double, _ y: Double) { path.addLine(to: CGPoint(x: x, y: y)) }
  func quadraticBezierTo(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
    path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
  }
  func cubicTo(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ x: Double, _ y: Double) {
    path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: ax, y: ay), control2: CGPoint(x: bx, y: by))
  }
  func close() { path.closeSubpath() }
  // Dart Path.getBounds includes the control points, matching CGPath.boundingBox.
  func getBounds() -> SceneCatalogVectorRect { .init(rect: path.boundingBox) }
}
struct SceneCatalogVectorColor {
  let rgba: SIMD4<Float>
  init(_ argb: UInt32) {
    rgba = SIMD4(Float((argb >> 16) & 255) / 255, Float((argb >> 8) & 255) / 255,
                 Float(argb & 255) / 255, Float((argb >> 24) & 255) / 255)
  }
  init(rgba: SIMD4<Float>) { self.rgba = rgba }
  func withValues(alpha: Double) -> Self {
    Self(rgba: SIMD4(rgba.x, rgba.y, rgba.z, Float(alpha)))
  }
  static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self {
    Self(rgba: simd_clamp(a.rgba + (b.rgba - a.rgba) * Float(t), SIMD4(repeating: 0), SIMD4(repeating: 1)))
  }
}
enum SceneCatalogVectorColors {
  static let white = SceneCatalogVectorColor(0xFFFFFFFF)
  static let black = SceneCatalogVectorColor(0xFF000000)
  static let black38 = SceneCatalogVectorColor(0x61000000)
  static let black54 = SceneCatalogVectorColor(0x8A000000)
  static let transparent = SceneCatalogVectorColor(0)
}
struct SceneCatalogVectorAlignment {
  let x: Double
  let y: Double
  init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
  static let center = Self(0, 0)
  static let topCenter = Self(0, -1)
  static let bottomCenter = Self(0, 1)
  static let centerLeft = Self(-1, 0)
  static let centerRight = Self(1, 0)
  static let topLeft = Self(-1, -1)
  static let bottomRight = Self(1, 1)
  func within(_ rect: SceneCatalogVectorRect) -> SIMD2<Float> {
    SIMD2(Float(rect.center.dx + x * rect.width / 2), Float(rect.center.dy + y * rect.height / 2))
  }
}
struct SceneCatalogVectorGradient {
  let radial: Bool
  let start: SIMD2<Float>
  let end: SIMD2<Float>
  let radius: Float
  let colors: [SceneCatalogVectorColor]
  let stops: [Double]
  var sweep = false
}
enum SceneCatalogVectorUIGradient {
  static func linear(_ start: SceneCatalogVectorOffset, _ end: SceneCatalogVectorOffset,
                     _ colors: [SceneCatalogVectorColor], _ stops: [Double]? = nil) -> SceneCatalogVectorGradient {
    .init(radial: false, start: SIMD2(Float(start.dx), Float(start.dy)),
          end: SIMD2(Float(end.dx), Float(end.dy)), radius: 0, colors: colors,
          stops: stops ?? colors.indices.map { Double($0) / Double(colors.count - 1) })
  }
  static func radial(_ center: SceneCatalogVectorOffset, _ radius: Double,
                     _ colors: [SceneCatalogVectorColor], _ stops: [Double]? = nil) -> SceneCatalogVectorGradient {
    .init(radial: true, start: SIMD2(Float(center.dx), Float(center.dy)), end: .zero,
          radius: Float(radius), colors: colors,
          stops: stops ?? colors.indices.map { Double($0) / Double(colors.count - 1) })
  }
  static func sweep(_ center: SceneCatalogVectorOffset, _ colors: [SceneCatalogVectorColor],
                    _ stops: [Double]? = nil) -> SceneCatalogVectorGradient {
    var gradient = radial(center, 1, colors, stops); gradient.sweep = true; return gradient
  }
}
struct SceneCatalogVectorLinearGradient {
  let begin: SceneCatalogVectorAlignment
  let end: SceneCatalogVectorAlignment
  let colors: [SceneCatalogVectorColor]
  let stops: [Double]?
  init(begin: SceneCatalogVectorAlignment = .centerLeft, end: SceneCatalogVectorAlignment = .centerRight,
       colors: [SceneCatalogVectorColor], stops: [Double]? = nil) {
    self.begin = begin; self.end = end; self.colors = colors; self.stops = stops
  }
  func createShader(_ rect: SceneCatalogVectorRect) -> SceneCatalogVectorGradient {
    .init(radial: false, start: begin.within(rect), end: end.within(rect), radius: 0,
          colors: colors, stops: stops ?? colors.indices.map { Double($0) / Double(colors.count - 1) })
  }
}
struct SceneCatalogVectorRadialGradient {
  let center: SceneCatalogVectorAlignment
  let radius: Double
  let colors: [SceneCatalogVectorColor]
  let stops: [Double]?
  init(center: SceneCatalogVectorAlignment = .center, radius: Double = 0.5,
       colors: [SceneCatalogVectorColor], stops: [Double]? = nil) {
    self.center = center; self.radius = radius; self.colors = colors; self.stops = stops
  }
  func createShader(_ rect: SceneCatalogVectorRect) -> SceneCatalogVectorGradient {
    .init(radial: true, start: center.within(rect), end: .zero,
          radius: Float(radius * min(rect.width, rect.height)), colors: colors,
          stops: stops ?? colors.indices.map { Double($0) / Double(colors.count - 1) })
  }
}
enum SceneCatalogVectorPaintingStyle { case fill, stroke }
enum SceneCatalogVectorStrokeCap { case butt, round, square }
enum SceneCatalogVectorStrokeJoin { case miter, round, bevel }
enum SceneCatalogVectorBlendMode { case srcOver, plus, screen }
enum SceneCatalogVectorBlurStyle { case normal }
struct SceneCatalogVectorMaskFilter {
  let sigma: Double
  static func blur(_ style: SceneCatalogVectorBlurStyle, _ sigma: Double) -> Self { .init(sigma: sigma) }
}
final class SceneCatalogVectorPaint {
  var color = SceneCatalogVectorColors.black
  var shader: SceneCatalogVectorGradient?
  var maskFilter: SceneCatalogVectorMaskFilter?
  var style = SceneCatalogVectorPaintingStyle.fill
  var strokeWidth = 0.0
  var strokeCap = SceneCatalogVectorStrokeCap.butt
  var strokeJoin = SceneCatalogVectorStrokeJoin.miter
  var blendMode = SceneCatalogVectorBlendMode.srcOver
}
final class SceneCatalogVectorCanvas {
  struct RoundedBlurShape {
    let rect: CGRect
    let radius: Double
  }
  struct Stroke {
    let path: CGPath
    let width: Double
    let cap: CGLineCap
    let join: CGLineJoin
    var transform = CGAffineTransform.identity
  }
  struct Draw {
    let path: CGPath
    let color: SceneCatalogVectorColor
    let gradient: SceneCatalogVectorGradient?
    let sigma: Double
    let additive: Bool
    let clip: CGPath?
    let stroke: Stroke?
    var roundedBlur: RoundedBlurShape? = nil
    var solidCircle: RoundedBlurShape? = nil
    var alphaScale: Float = 1
    var transform = CGAffineTransform.identity
    var localBlurPath: CGPath? = nil
    var screen = false
    var sourceBounds: CGRect? = nil
    var ambientBlurPath: CGPath? = nil
    func atScale(_ scale: Float) -> Draw {
      guard let stroke else { return self }
      let effectiveScale = scale * Float(max(hypot(transform.a, transform.b), hypot(transform.c, transform.d)))
      guard Float(stroke.width) * effectiveScale < 1 else { return self }
      let adjusted = stroke.path.copy(strokingWithWidth: 1 / Double(effectiveScale),
        lineCap: stroke.cap, lineJoin: stroke.join, miterLimit: 4)
      var matrix = transform
      return Draw(path: adjusted.copy(using: &matrix)!, color: color, gradient: gradient, sigma: sigma,
                  additive: additive, clip: clip, stroke: nil,
                  alphaScale: stroke.width == 0 ? 1 : min(1, Float(stroke.width) * effectiveScale * 2),
                  transform: transform, localBlurPath: localBlurPath == nil ? nil : adjusted, screen: screen,
                  sourceBounds: sourceBounds)
    }
  }
  private(set) var draws: [Draw] = []
  private var clips: [CGPath?] = [nil]
  private var transforms: [CGAffineTransform] = [.identity]
  func save() { clips.append(clips.last!); transforms.append(transforms.last!) }
  func restore() { precondition(clips.count > 1); clips.removeLast(); transforms.removeLast() }
  func translate(_ x: Double, _ y: Double) { transforms[transforms.count - 1] = transforms.last!.translatedBy(x: x, y: y) }
  func rotate(_ angle: Double) { transforms[transforms.count - 1] = transforms.last!.rotated(by: angle) }
  func scale(_ x: Double, _ y: Double) { transforms[transforms.count - 1] = transforms.last!.scaledBy(x: x, y: y) }
  func clipPath(_ path: SceneCatalogVectorPath) {
    // The installed painter has exactly one non-nested clip path.
    precondition(clips.last! == nil, "Nested vector clips require an explicit implementation")
    var transform = transforms.last!
    clips[clips.count - 1] = path.path.copy(using: &transform)!
  }
  func drawPath(_ path: SceneCatalogVectorPath, _ paint: SceneCatalogVectorPaint) {
    // DisplayListBuilder::DrawPath recognizes rectangular paths before dispatch.
    var rectangle = CGRect.zero
    let isRectangle = path.path.isRect(&rectangle)
    record(path.path, paint, roundedBlur: isRectangle ? .init(rect: rectangle, radius: 0) : nil)
  }
  func drawRect(_ rect: SceneCatalogVectorRect, _ paint: SceneCatalogVectorPaint) {
    record(CGPath(rect: rect.rect, transform: nil), paint, roundedBlur: .init(rect: rect.rect, radius: 0))
  }
  func drawRRect(_ rect: SceneCatalogVectorRRect, _ paint: SceneCatalogVectorPaint) {
    record(CGPath(roundedRect: rect.outerRect.rect, cornerWidth: rect.radius, cornerHeight: rect.radius, transform: nil), paint,
           roundedBlur: .init(rect: rect.outerRect.rect, radius: rect.radius))
  }
  func drawCircle(_ center: SceneCatalogVectorOffset, _ radius: Double, _ paint: SceneCatalogVectorPaint) {
    drawOval(.fromCircle(center: center, radius: radius), paint)
  }
  func drawOval(_ rect: SceneCatalogVectorRect, _ paint: SceneCatalogVectorPaint) {
    record(CGPath(ellipseIn: rect.rect, transform: nil), paint,
           roundedBlur: rect.width == rect.height ? .init(rect: rect.rect, radius: rect.width / 2) : nil)
  }
  func drawLine(_ a: SceneCatalogVectorOffset, _ b: SceneCatalogVectorOffset, _ paint: SceneCatalogVectorPaint) {
    let path = CGMutablePath(); path.move(to: a.point); path.addLine(to: b.point)
    record(path, paint, forceStroke: true)
  }
  func drawArc(_ rect: SceneCatalogVectorRect, _ start: Double, _ sweep: Double,
               _ useCenter: Bool, _ paint: SceneCatalogVectorPaint) {
    let path = CGMutablePath()
    var transform = CGAffineTransform(translationX: rect.center.dx, y: rect.center.dy)
      .scaledBy(x: rect.width / 2, y: rect.height / 2)
    if useCenter { path.move(to: .zero) }
    path.addArc(center: .zero, radius: 1, startAngle: start, endAngle: start + sweep, clockwise: sweep < 0)
    if useCenter { path.closeSubpath() }
    record(path.copy(using: &transform)!, paint)
  }
  private func record(_ source: CGPath, _ paint: SceneCatalogVectorPaint, forceStroke: Bool = false,
                      roundedBlur: RoundedBlurShape? = nil) {
    let path: CGPath
    var stroke: Stroke?
    if forceStroke || paint.style == .stroke {
      let cap: CGLineCap = paint.strokeCap == .round ? .round : paint.strokeCap == .square ? .square : .butt
      let join: CGLineJoin = paint.strokeJoin == .round ? .round : paint.strokeJoin == .bevel ? .bevel : .miter
      path = source.copy(strokingWithWidth: max(paint.strokeWidth, 0.0001), lineCap: cap, lineJoin: join, miterLimit: 4)
      stroke = Stroke(path: source.copy()!, width: paint.strokeWidth, cap: cap, join: join)
    } else { path = source.copy()! }
    var transform = transforms.last!
    draws.append(.init(path: path.copy(using: &transform)!, color: paint.color, gradient: paint.shader,
                       sigma: paint.maskFilter?.sigma ?? 0, additive: paint.blendMode == .plus, clip: clips.last!, stroke: stroke,
                       roundedBlur: transform.isIdentity && stroke == nil && paint.shader == nil && (paint.maskFilter?.sigma ?? 0) > 0.5 + 0.001 / sqrt(3)
                         ? roundedBlur : nil,
                       solidCircle: transform.isIdentity && stroke == nil && paint.shader == nil && paint.maskFilter == nil
                         && roundedBlur?.rect.width == roundedBlur?.rect.height
                         && roundedBlur?.radius == (roundedBlur?.rect.width ?? -1) * 0.5 ? roundedBlur : nil,
                       transform: transform,
                       localBlurPath: !transform.isIdentity && paint.maskFilter != nil ? path : nil,
                       screen: paint.blendMode == .screen,
                       sourceBounds: source.boundingBox.insetBy(
                         dx: stroke == nil ? 0 : -max(paint.strokeWidth, 1) * (paint.strokeJoin == .miter ? 2 : paint.strokeCap == .square ? sqrt(2) / 2 : 0.5),
                         dy: stroke == nil ? 0 : -max(paint.strokeWidth, 1) * (paint.strokeJoin == .miter ? 2 : paint.strokeCap == .square ? sqrt(2) / 2 : 0.5)),
                       ambientBlurPath: stroke == nil && paint.shader == nil && (paint.maskFilter?.sigma ?? 0) > 0.5 + 0.001 / sqrt(3)
                         ? source.copy() : nil))
  }
}

@available(iOS 15.0, *)
final class SceneCatalogVectorRenderer {
  static let intermediateTextureBudgetBytes = 256 * 1024 * 1024
  static let intermediatePassBudget = 192
  struct Statistics {
    let drawCount: Int
    let analyticBlurCount: Int
    let atlasCount: Int
    let rasterPassCount: Int
    let computePassCount: Int
    let intermediateBytes: Int
    let gpuSeconds: Double
    var intermediatePassCount: Int { rasterPassCount + computePassCount - 1 }
  }
  private(set) var lastStatistics: Statistics?
  private(set) var maximumObservedIntermediateBytes = 0
  private var allocationBytes = 0
  private let textureBudgetBytes: Int
  private let intermediatePassBudget: Int
  var retainedIntermediateBytes: Int {
    var textures = scratch.values.flatMap { [$0.mask, $0.horizontal, $0.blurred] }
    if let sourceScratch { textures += [sourceScratch.mask, sourceScratch.multisample, sourceScratch.stencil] }
    if let colorTarget { textures += [colorTarget.multisample, colorTarget.stencil, colorTarget.fallbackMask] }
    var identities = Set<ObjectIdentifier>()
    return textures.reduce(0) { bytes, texture in
      identities.insert(ObjectIdentifier(texture)).inserted ? bytes + texture.allocatedSize : bytes
    }
  }
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let windingPipeline: MTLRenderPipelineState
  private let maskPipeline: MTLRenderPipelineState
  private let sourceOverPipeline: MTLRenderPipelineState
  private let plusPipeline: MTLRenderPipelineState
  private let screenPipeline: MTLRenderPipelineState
  private let shadowSourceOverPipeline: MTLRenderPipelineState
  private let shadowPlusPipeline: MTLRenderPipelineState
  private let shadowScreenPipeline: MTLRenderPipelineState
  private let windingState: MTLDepthStencilState
  private let maskState: MTLDepthStencilState
  private let sampler: MTLSamplerState
  private let horizontalBlur: MTLComputePipelineState
  private let verticalBlur: MTLComputePipelineState
  private let downsamplePipeline: MTLComputePipelineState
  private let directWindingPipeline: MTLRenderPipelineState
  private let clearStencilPipeline: MTLRenderPipelineState
  private let clearStencilState: MTLDepthStencilState
  private let noStencilState: MTLDepthStencilState
  private var colorTarget: ColorTarget?
  private var sourceScratch: Scratch?
  private var scratch: [String: Scratch] = [:]
  private var targetSize = SIMD2<Int>(0, 0)
  private struct Scratch {
    let mask: MTLTexture
    let multisample: MTLTexture
    let stencil: MTLTexture
    let blurred: MTLTexture
    let horizontal: MTLTexture
  }
  private struct Mask {
    let texture: MTLTexture
    let region: SIMD4<Float>
  }
  private struct Parameters {
    var target: SIMD4<Float>
    var region: SIMD4<Float>
    var clipRegion: SIMD4<Float>
    var startEnd: SIMD4<Float>
    var color: SIMD4<Float>
    var info: SIMD4<Float>
    var maskUV: SIMD4<Float>
    var clipUV: SIMD4<Float>
    var flags: SIMD4<Float>
    var blurCenterAdjust: SIMD4<Float>
    var blurRadiusExponent: SIMD4<Float>
    var blurFade: SIMD4<Float>
    var localRowX: SIMD4<Float>
    var localRowY: SIMD4<Float>
    var maskSourceRegion: SIMD4<Float>
    var maskScale: SIMD4<Float>
    var gradientSnapshot: SIMD4<Float>
  }
  private struct Tile {
    let path: CGPath
    var region: CGRect
    let sigma: SIMD2<Float>
    let radii: SIMD2<Int>
    var filterScale: Float
    var identifier = 0
    var page = 0
    var origin = SIMD2<Int>(0, 0)
    var sourceScale: SIMD2<Float>? = nil
    var color = SIMD4<Float>(repeating: 1)
    var sourceRegion: CGRect? = nil
    var rasterWidth: Int { Int(round(Float(region.width) * filterScale)) }
    var rasterHeight: Int { Int(round(Float(region.height) * filterScale)) }
  }
  private struct ColorTarget {
    let multisample: MTLTexture
    let stencil: MTLTexture
    let fallbackMask: MTLTexture
  }
  private struct Cell {
    var placement: SIMD4<UInt32>
    var address: SIMD4<UInt32>
    var radii: SIMD4<UInt32>
    var sampling = SIMD4<Float>.zero
  }
  private struct TilePaint { var region: SIMD4<Float>; var color: SIMD4<Float> }
  private struct RoundedBlur {
    let kind: Float
    let region: CGRect
    let centerAdjust: SIMD4<Float>
    let radiusExponent: SIMD4<Float>
    let fade: SIMD4<Float>
  }
  // Flutter's BSD-licensed SolidRRectLikeBlurContents::PopulateFragContext.
  // This is the original analytic blur route, not the Gaussian mask route.
  private static func roundedBlur(_ draw: SceneCatalogVectorCanvas.Draw, scale: SIMD2<Float>) -> RoundedBlur? {
    if let circle = draw.solidCircle {
      let rect = circle.rect.insetBy(dx: -1 / Double(max(scale.x, scale.y)), dy: -1 / Double(max(scale.x, scale.y)))
      return RoundedBlur(kind: 2,
        region: CGRect(x: rect.minX * Double(scale.x), y: rect.minY * Double(scale.y),
                       width: rect.width * Double(scale.x), height: rect.height * Double(scale.y)),
        centerAdjust: SIMD4(Float(circle.rect.midX), Float(circle.rect.midY), 0, 0),
        radiusExponent: SIMD4(Float(circle.radius), 0, 0, 0), fade: .zero)
    }
    guard let shape = draw.roundedBlur else { return nil }
    let rect = shape.rect.standardized
    let blurSigma = min(max(Float(draw.sigma), 0.001), 500 / max(scale.x, scale.y))
    let padding = blurSigma * min(blurSigma / 47.6 + 2.5, 3.5)
    let sigma = max(blurSigma * sqrt(2), 1)
    var size = SIMD2<Float>(Float(rect.width), Float(rect.height))
    guard size.x > 0, size.y > 0 else { return nil }
    let center = SIMD2<Float>(Float(rect.midX), Float(rect.midY))
    let minEdge = min(size.x, size.y)
    let radius = min(max(Float(shape.radius), 0.001), minEdge * 0.5)
    let rMax = Double(minEdge) * 0.5
    let r0 = min(hypot(Double(radius), Double(sigma) * 1.15), rMax)
    let r1 = Float(min(hypot(Double(radius), Double(sigma) * 2), rMax))
    let exponent = Float(2 * Double(r1) / r0)
    let sInv = 1 / sigma
    let vOverS = size * (sInv * 0.5)
    let delta = Float(1.25 * Double(sigma) * Double(exp(-vOverS.x * vOverS.x) - exp(-vOverS.y * vOverS.y)))
    size += SIMD2(min(delta, 0), max(delta, 0))
    let adjust = size * 0.5 - SIMD2(repeating: r1)
    func erf7(_ value: Float) -> Float {
      var x = value * (2 / sqrt(Float.pi)); let xx = x * x
      x += (0.24295 + (0.03395 + 0.0104 * xx) * xx) * (x * xx)
      return x / sqrt(1 + x * x)
    }
    let fadeScale = 0.5 * erf7(sInv * 0.5 * (max(size.x, size.y) - 0.5 * radius))
    let expanded = rect.insetBy(dx: -Double(padding), dy: -Double(padding))
    return RoundedBlur(kind: 1,
      region: CGRect(x: expanded.minX * Double(scale.x), y: expanded.minY * Double(scale.y),
                     width: expanded.width * Double(scale.x), height: expanded.height * Double(scale.y)),
      centerAdjust: SIMD4(center.x, center.y, adjust.x, adjust.y),
      radiusExponent: SIMD4(r1, exponent, 1 / exponent, 0),
      fade: SIMD4(sInv, minEdge, fadeScale, 0))
  }
  init(device: MTLDevice, textureBudgetBytes: Int = SceneCatalogVectorRenderer.intermediateTextureBudgetBytes,
       intermediatePassBudget: Int = SceneCatalogVectorRenderer.intermediatePassBudget) throws {
    self.device = device
    guard textureBudgetBytes > 0 else { throw Failure("vector_intermediate_texture_budget") }
    self.textureBudgetBytes = textureBudgetBytes
    guard intermediatePassBudget > 0 else { throw Failure("vector_intermediate_pass_budget") }
    self.intermediatePassBudget = intermediatePassBudget
    guard let queue = device.makeCommandQueue() else { throw Failure("vector_command_queue") }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.source, options: nil)
    horizontalBlur = try device.makeComputePipelineState(function: library.makeFunction(name: "vectorBlurHorizontal")!)
    verticalBlur = try device.makeComputePipelineState(function: library.makeFunction(name: "vectorBlurVertical")!)
    downsamplePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "vectorDownsample")!)
    func pipeline(vertex: String, fragment: String, mask: Bool = false,
                  writes: Bool = true, additive: Bool = false, screen: Bool = false, resolve: Bool = false) throws -> MTLRenderPipelineState {
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: vertex)
      descriptor.fragmentFunction = library.makeFunction(name: fragment)
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      if !resolve {
        descriptor.rasterSampleCount = 4
        descriptor.stencilAttachmentPixelFormat = .stencil8
        descriptor.colorAttachments[0].writeMask = writes ? .all : []
      }
      if !mask && !resolve {
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = additive ? .one : screen ? .oneMinusSourceColor : .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
      }
      return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    windingPipeline = try pipeline(vertex: "vectorPathVertex", fragment: "vectorMaskFragment", mask: true, writes: false)
    maskPipeline = try pipeline(vertex: "vectorTileVertex", fragment: "vectorTileFragment", mask: true)
    sourceOverPipeline = try pipeline(vertex: "vectorColorVertex", fragment: "vectorColorFragment")
    plusPipeline = try pipeline(vertex: "vectorColorVertex", fragment: "vectorColorFragment", additive: true)
    screenPipeline = try pipeline(vertex: "vectorColorVertex", fragment: "vectorColorFragment", screen: true)
    shadowSourceOverPipeline = try pipeline(vertex: "vectorShadowVertex", fragment: "vectorShadowFragment")
    shadowPlusPipeline = try pipeline(vertex: "vectorShadowVertex", fragment: "vectorShadowFragment", additive: true)
    shadowScreenPipeline = try pipeline(vertex: "vectorShadowVertex", fragment: "vectorShadowFragment", screen: true)
    directWindingPipeline = try pipeline(vertex: "vectorPathVertex", fragment: "vectorColorFragment", writes: false)
    clearStencilPipeline = try pipeline(vertex: "vectorColorVertex", fragment: "vectorColorFragment", writes: false)
    let winding = MTLDepthStencilDescriptor()
    winding.frontFaceStencil.stencilCompareFunction = .always
    winding.frontFaceStencil.depthStencilPassOperation = .incrementWrap
    winding.backFaceStencil.stencilCompareFunction = .always
    winding.backFaceStencil.depthStencilPassOperation = .decrementWrap
    let mask = MTLDepthStencilDescriptor()
    mask.frontFaceStencil.stencilCompareFunction = .notEqual
    mask.frontFaceStencil.writeMask = 0
    mask.backFaceStencil.stencilCompareFunction = .notEqual
    mask.backFaceStencil.writeMask = 0
    guard let windingState = device.makeDepthStencilState(descriptor: winding),
          let maskState = device.makeDepthStencilState(descriptor: mask) else { throw Failure("vector_stencil_states") }
    self.windingState = windingState; self.maskState = maskState
    let clear = MTLDepthStencilDescriptor()
    clear.frontFaceStencil.depthStencilPassOperation = .replace
    clear.backFaceStencil.depthStencilPassOperation = .replace
    guard let clearState = device.makeDepthStencilState(descriptor: clear),
          let none = device.makeDepthStencilState(descriptor: MTLDepthStencilDescriptor()) else { throw Failure("vector_stencil_clear") }
    clearStencilState = clearState; noStencilState = none
    let sampling = MTLSamplerDescriptor()
    sampling.minFilter = .linear; sampling.magFilter = .linear
    sampling.sAddressMode = .clampToZero; sampling.tAddressMode = .clampToZero
    guard let sampler = device.makeSamplerState(descriptor: sampling) else { throw Failure("vector_sampler") }
    self.sampler = sampler
  }

  func render(canvas: SceneCatalogVectorCanvas, logicalWidth: Double, logicalHeight: Double,
              width: Int, height: Int, outputAllocator: SceneSurfaceNativeOutputAllocator?) throws -> MTLTexture {
    guard logicalWidth.isFinite, logicalHeight.isFinite, logicalWidth > 0, logicalHeight > 0,
          width > 0, height > 0, width <= 8192, height <= 8192 else { throw Failure("vector_dimensions") }
    if targetSize != SIMD2(width, height) { scratch.removeAll(); sourceScratch = nil; colorTarget = nil; targetSize = SIMD2(width, height) }
    allocationBytes = retainedIntermediateBytes
    guard let output = try SceneSurfaceNativeOutputAllocator.makeTexture(
      device: device, width: width, height: height, allocator: outputAllocator
    ), let command = queue.makeCommandBuffer() else { throw Failure("vector_output") }
    let scale = SIMD2<Float>(Float(Double(width) / logicalWidth), Float(Double(height) / logicalHeight))
    let draws = canvas.draws.map { $0.atScale(max(scale.x, scale.y)) }
    let roundedBlurs = draws.map { Self.roundedBlur($0, scale: scale) }
    let ambientMeshes = draws.enumerated().map { index, draw -> SceneCatalogAmbientShadow.Mesh? in
      guard roundedBlurs[index] == nil, let path = draw.ambientBlurPath else { return nil }
      let t = draw.transform
      let deviceTransform = CGAffineTransform(a: t.a * CGFloat(scale.x), b: t.b * CGFloat(scale.y),
        c: t.c * CGFloat(scale.x), d: t.d * CGFloat(scale.y),
        tx: t.tx * CGFloat(scale.x), ty: t.ty * CGFloat(scale.y))
      let basis = max(hypot(deviceTransform.a, deviceTransform.b), hypot(deviceTransform.c, deviceTransform.d))
      return SceneCatalogAmbientShadow.makeVertices(path: path, transform: deviceTransform,
        deviceRadius: draw.sigma * 2.8 * basis)
    }
    var shadowVertices: [SIMD4<Float>] = []
    let shadowRanges = ambientMeshes.map { mesh -> Range<Int> in
      let start = shadowVertices.count
      if let mesh {
        for index in mesh.indices {
          let p = mesh.positions[Int(index)]
          shadowVertices.append(SIMD4(p.x, p.y, mesh.penumbra[Int(index)], 0))
        }
      }
      return start..<shadowVertices.count
    }
    if colorTarget == nil { colorTarget = try makeColorTarget(width: width, height: height) }
    guard let colorTarget else { throw Failure("vector_color_target") }
    var tiles: [Tile] = []
    var drawTiles: [(Int, Int?)] = []
    var directRanges: [Range<Int>] = []
    var directVertices: [SIMD2<Float>] = []
    var clipTiles: [ObjectIdentifier: Int] = [:]
    for (drawIndex, draw) in draws.enumerated() {
      let analyticTile = roundedBlurs[drawIndex].map {
        Tile(path: draw.path, region: $0.region, sigma: .zero, radii: .zero, filterScale: 1)
      }
      let shadowTile = ambientMeshes[drawIndex].map { _ in
        Tile(path: draw.path, region: CGRect(x: 0, y: 0, width: width, height: height),
          sigma: .zero, radii: .zero, filterScale: 1)
      }
      let localScale = SIMD2<Float>(
        hypot(Float(draw.transform.a) * scale.x, Float(draw.transform.b) * scale.y),
        hypot(Float(draw.transform.c) * scale.x, Float(draw.transform.d) * scale.y))
      let filterScale = draw.localBlurPath == nil ? scale : localScale
      let sourceClip: CGRect? = draw.gradient == nil ? nil : CGRect(
        x: -Double(draw.transform.tx) * Double(scale.x), y: -Double(draw.transform.ty) * Double(scale.y),
        width: Double(width), height: Double(height))
      guard var tile = analyticTile ?? shadowTile ?? Self.tile(path: draw.localBlurPath ?? draw.path, sigma: draw.sigma,
          scale: filterScale, width: width, height: height, bounded: draw.localBlurPath == nil,
          sourceBounds: draw.sourceBounds, sourceClip: sourceClip) else {
        directRanges.append(0..<0)
        drawTiles.append((-1, nil)); continue
      }
      tile.sourceScale = filterScale
      if draw.gradient == nil {
        let rgba = draw.color.rgba
        tile.color = SIMD4(rgba.x * rgba.w, rgba.y * rgba.w, rgba.z * rgba.w, rgba.w) * draw.alphaScale
      }
      let maskIndex: Int
      let first = directVertices.count
      if ambientMeshes[drawIndex] != nil {
        maskIndex = -4
      } else if roundedBlurs[drawIndex] != nil {
        maskIndex = -3
      } else if draw.sigma == 0 {
        maskIndex = -2
        directVertices.append(contentsOf: Self.triangles(path: draw.path,
          tolerance: 0.08 / Double(max(scale.x, scale.y))).map { $0 * scale })
      } else { maskIndex = tiles.count; tiles.append(tile) }
      directRanges.append(first..<directVertices.count)
      var clipIndex: Int?
      if let path = draw.clip {
        let key = ObjectIdentifier(path)
        if let existing = clipTiles[key] { clipIndex = existing }
        else if let clip = Self.tile(path: path, sigma: 0, scale: scale, width: width, height: height) {
          clipIndex = tiles.count; clipTiles[key] = tiles.count; tiles.append(clip)
        } else { drawTiles.append((-1, nil)); continue }
      }
      drawTiles.append((maskIndex, clipIndex))
    }
    let pages = Self.pack(&tiles)
    for index in tiles.indices { tiles[index].identifier = index }
    let liveScratchKeys = Set(pages.enumerated().map { "\($0.offset):\($0.element.x)x\($0.element.y)" })
    scratch = scratch.filter { liveScratchKeys.contains($0.key) }
    var physicalTiles = tiles
    for index in physicalTiles.indices {
      physicalTiles[index].filterScale = 1
      if let source = physicalTiles[index].sourceRegion { physicalTiles[index].region = source }
    }
    let physicalPages = Self.pack(&physicalTiles, pageLimit: 1024)
    let downsamplePasses = physicalPages.indices.reduce(0) { count, page in
      count + Set(physicalTiles.filter { $0.page == page }.map { tiles[$0.identifier].page }).count
    }
    guard physicalPages.count + pages.count * 2 + downsamplePasses <= intermediatePassBudget else {
      throw Failure("vector_intermediate_pass_budget")
    }
    let sourceWidth = physicalPages.map(\.x).max() ?? 0, sourceHeight = physicalPages.map(\.y).max() ?? 0
    // The preceding render synchronously waited for GPU completion. Evict old
    // dimensions before allocating their replacement; never retain a size history.
    if sourceScratch?.mask.width != sourceWidth || sourceScratch?.mask.height != sourceHeight {
      sourceScratch = nil
    }
    allocationBytes = retainedIntermediateBytes
    var atlases: [Scratch] = []
    for (page, size) in pages.enumerated() {
      let atlas = try makeScratch(width: size.x, height: size.y, retained: false, page: page)
      atlases.append(atlas)
    }
    if !physicalPages.isEmpty {
      if sourceScratch == nil {
        sourceScratch = try makeSourceScratch(width: sourceWidth, height: sourceHeight)
      }
      guard let sourceScratch else { throw Failure("vector_source_scratch") }
      for page in physicalPages.indices {
        let sources = physicalTiles.filter { $0.page == page }
        try encodeCoverage(tiles: sources, atlas: sourceScratch, scale: scale, command: command)
        for targetPage in Set(sources.map { tiles[$0.identifier].page }).sorted() {
          let subset = sources.filter { tiles[$0.identifier].page == targetPage }
          try encodeDownsample(sources: subset, targets: tiles, source: sourceScratch.mask,
                               destination: atlases[targetPage].mask, command: command)
        }
      }
    }
    for page in pages.indices {
      try encodeBlur(tiles: tiles.filter { $0.page == page }, atlas: atlases[page], command: command)
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = colorTarget.multisample
    pass.colorAttachments[0].resolveTexture = output
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .multisampleResolve
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    pass.stencilAttachment.texture = colorTarget.stencil
    pass.stencilAttachment.loadAction = .clear
    pass.stencilAttachment.storeAction = .dontCare
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Failure("vector_color_encoder") }
    let directBuffer = directVertices.withUnsafeBytes { bytes in
      bytes.isEmpty ? nil : device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
    }
    let shadowBuffer = shadowVertices.withUnsafeBytes { bytes in
      bytes.isEmpty ? nil : device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
    }
    // A valid fallback is bound even when the direct fragment branch does not sample it.
    let fallbackMask = atlases.first?.blurred ?? colorTarget.fallbackMask
    for (drawIndex, draw) in draws.enumerated() {
      let (maskIndex, clipIndex) = drawTiles[drawIndex]
      if maskIndex == -1 { continue }
      let direct = maskIndex == -2
      let shadow = maskIndex == -4
      let roundedBlur = roundedBlurs[drawIndex]
      let mask: Tile
      if let roundedBlur {
        mask = Tile(path: draw.path, region: roundedBlur.region, sigma: .zero, radii: .zero, filterScale: 1)
      } else if shadow {
        mask = Tile(path: draw.path, region: CGRect(x: 0, y: 0, width: width, height: height),
          sigma: .zero, radii: .zero, filterScale: 1)
      } else {
        mask = direct ? Self.tile(path: draw.path, sigma: 0, scale: scale, width: width, height: height)! : tiles[maskIndex]
      }
      let clip = clipIndex.map { tiles[$0] }
      let maskTexture = direct || shadow || roundedBlur != nil ? fallbackMask : atlases[mask.page].blurred
      let clipTexture = clip.map { atlases[$0.page].blurred } ?? maskTexture
      func region(_ tile: Tile) -> SIMD4<Float> {
        SIMD4(Float(tile.region.minX), Float(tile.region.minY), Float(tile.region.width), Float(tile.region.height))
      }
      func uv(_ tile: Tile, _ texture: MTLTexture) -> SIMD4<Float> {
        SIMD4(Float(tile.origin.x) / Float(texture.width), Float(tile.origin.y) / Float(texture.height),
              Float(tile.rasterWidth) / Float(texture.width), Float(tile.rasterHeight) / Float(texture.height))
      }
      encoder.setRenderPipelineState(draw.additive ? plusPipeline : draw.screen ? screenPipeline : sourceOverPipeline)
      let gradient = draw.gradient
      let inverse = draw.transform.inverted()
      let sourceScale = mask.sourceScale ?? scale
      var outputRegion = region(mask)
      var gradientSnapshot = SIMD4<Float>.zero
      if gradient != nil, draw.sigma > 0, let bounds = draw.sourceBounds {
        let radius = ceil(Double(max(0, (Self.impellerScaleSigma(Float(draw.sigma)) - 0.5) * sqrt(3))))
        let localBounds = bounds.insetBy(dx: -radius, dy: -radius)
        let worldBounds = localBounds.applying(draw.transform)
        let physical = CGRect(x: worldBounds.minX * Double(scale.x), y: worldBounds.minY * Double(scale.y),
          width: worldBounds.width * Double(scale.x), height: worldBounds.height * Double(scale.y)).insetBy(dx: -1, dy: -1)
          .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        gradientSnapshot = SIMD4(Float(physical.minX), Float(physical.minY), Float(ceil(physical.width)), Float(ceil(physical.height)))
      }
      if draw.localBlurPath != nil {
        let localRect = CGRect(x: mask.region.minX / Double(sourceScale.x), y: mask.region.minY / Double(sourceScale.y),
          width: mask.region.width / Double(sourceScale.x), height: mask.region.height / Double(sourceScale.y))
        let world = localRect.applying(draw.transform)
        outputRegion = SIMD4(Float(world.minX) * scale.x, Float(world.minY) * scale.y,
          Float(world.width) * scale.x, Float(world.height) * scale.y)
      }
      var parameters = Parameters(
        target: SIMD4(Float(width), Float(height), scale.x, scale.y), region: outputRegion,
        clipRegion: clip.map(region) ?? .zero,
        startEnd: SIMD4(gradient?.start.x ?? 0, gradient?.start.y ?? 0, gradient?.end.x ?? 0, gradient?.end.y ?? 0),
        color: draw.color.rgba,
        info: SIMD4(gradient == nil ? 0 : gradient!.sweep ? 3 : gradient!.radial ? 2 : 1,
                    Float(gradient?.colors.count ?? 0), gradient?.radius ?? 0, clip == nil ? 0 : 1),
        maskUV: uv(mask, maskTexture), clipUV: clip.map { uv($0, clipTexture) } ?? .zero,
        flags: SIMD4(1, direct || roundedBlur != nil ? 1 : 0, roundedBlur?.kind ?? 0, draw.alphaScale),
        blurCenterAdjust: roundedBlur?.centerAdjust ?? .zero,
        blurRadiusExponent: roundedBlur?.radiusExponent ?? .zero,
        blurFade: roundedBlur?.fade ?? .zero,
        localRowX: SIMD4(Float(inverse.a), Float(inverse.c), Float(inverse.tx), 0),
        localRowY: SIMD4(Float(inverse.b), Float(inverse.d), Float(inverse.ty), 0),
        maskSourceRegion: region(mask),
        maskScale: SIMD4(sourceScale.x, sourceScale.y, draw.localBlurPath == nil ? 0 : 1,
          draw.sigma > 0 && roundedBlur == nil ? (gradient == nil ? 2 : 1) : 0),
        gradientSnapshot: gradientSnapshot
      )
      encoder.setVertexBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
      encoder.setFragmentBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
      var colors = [SIMD4<Float>](repeating: .zero, count: 8)
      var stops = [Float](repeating: 0, count: 8)
      if let gradient {
        guard gradient.colors.count <= 8, gradient.colors.count >= 2,
              gradient.stops.count == gradient.colors.count else { throw Failure("vector_gradient_contract") }
        for index in gradient.colors.indices { colors[index] = gradient.colors[index].rgba; stops[index] = Float(gradient.stops[index]) }
      }
      colors.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
      stops.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
      encoder.setFragmentTexture(maskTexture, index: 0)
      encoder.setFragmentTexture(clipTexture, index: 1)
      encoder.setFragmentSamplerState(sampler, index: 0)
      if shadow {
        encoder.setRenderPipelineState(draw.additive ? shadowPlusPipeline : draw.screen ? shadowScreenPipeline : shadowSourceOverPipeline)
        encoder.setDepthStencilState(noStencilState)
        encoder.setVertexBuffer(shadowBuffer, offset: 0, index: 1)
        let range = shadowRanges[drawIndex]
        if !range.isEmpty { encoder.drawPrimitives(type: .triangle, vertexStart: range.lowerBound, vertexCount: range.count) }
        continue
      }
      if direct {
        // Reset only this draw's bounded stencil, then accumulate its winding.
        encoder.setRenderPipelineState(clearStencilPipeline)
        encoder.setDepthStencilState(clearStencilState)
        encoder.setStencilReferenceValue(0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.setRenderPipelineState(directWindingPipeline)
        encoder.setDepthStencilState(windingState)
        encoder.setVertexBuffer(directBuffer, offset: 0, index: 0)
        var target = SIMD4<Float>(0, 0, Float(width), Float(height))
        encoder.setVertexBytes(&target, length: 16, index: 1)
        let range = directRanges[drawIndex]
        encoder.drawPrimitives(type: .triangle, vertexStart: range.lowerBound, vertexCount: range.count)
        encoder.setVertexBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
        encoder.setRenderPipelineState(draw.additive ? plusPipeline : draw.screen ? screenPipeline : sourceOverPipeline)
        encoder.setDepthStencilState(maskState)
      } else { encoder.setDepthStencilState(noStencilState) }
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    encoder.endEncoding()
    command.commit(); command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? Failure("vector_command_failed") }
    lastStatistics = Statistics(
      drawCount: canvas.draws.count, analyticBlurCount: roundedBlurs.compactMap { $0 }.filter { $0.kind == 1 }.count + ambientMeshes.compactMap { $0 }.count, atlasCount: atlases.count,
      rasterPassCount: physicalPages.count + 1, computePassCount: atlases.count * 2 + downsamplePasses,
      intermediateBytes: retainedIntermediateBytes,
      gpuSeconds: max(0, command.gpuEndTime - command.gpuStartTime)
    )
    return output
  }

  private func makeIntermediateTexture(_ descriptor: MTLTextureDescriptor) throws -> MTLTexture {
    let required = device.heapTextureSizeAndAlign(descriptor: descriptor).size
    guard required <= textureBudgetBytes - allocationBytes else {
      throw Failure("vector_intermediate_texture_budget")
    }
    guard let texture = device.makeTexture(descriptor: descriptor) else { throw Failure("vector_intermediate_texture") }
    guard texture.allocatedSize <= textureBudgetBytes - allocationBytes else {
      throw Failure("vector_intermediate_texture_budget")
    }
    allocationBytes += texture.allocatedSize
    maximumObservedIntermediateBytes = max(maximumObservedIntermediateBytes, allocationBytes)
    return texture
  }

  private func makeColorTarget(width: Int, height: Int) throws -> ColorTarget {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
    descriptor.storageMode = .private; descriptor.usage = [.shaderRead]
    let fallbackMask = try makeIntermediateTexture(descriptor)
    descriptor.width = width; descriptor.height = height
    descriptor.textureType = .type2DMultisample; descriptor.sampleCount = 4; descriptor.usage = [.renderTarget]
    let multisample = try makeIntermediateTexture(descriptor)
    descriptor.pixelFormat = .stencil8
    let stencil = try makeIntermediateTexture(descriptor)
    return ColorTarget(multisample: multisample, stencil: stencil, fallbackMask: fallbackMask)
  }

  private func makeScratch(width: Int, height: Int, retained: Bool, page: Int = 0) throws -> Scratch {
    let key = "\(page):\(width)x\(height)"
    if !retained, let value = scratch[key] { return value }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.storageMode = .private; descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    let blurred = try makeIntermediateTexture(descriptor)
    let horizontal = try makeIntermediateTexture(descriptor)
    let mask = try makeIntermediateTexture(descriptor)
    let result = Scratch(mask: mask, multisample: mask, stencil: mask, blurred: blurred, horizontal: horizontal)
    if !retained { scratch[key] = result }
    return result
  }

  private func makeSourceScratch(width: Int, height: Int) throws -> Scratch {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.storageMode = .private; descriptor.usage = [.shaderRead, .renderTarget]
    let mask = try makeIntermediateTexture(descriptor)
    descriptor.textureType = .type2DMultisample; descriptor.sampleCount = 4
    descriptor.usage = [.renderTarget]
    let multisample = try makeIntermediateTexture(descriptor)
    descriptor.pixelFormat = .stencil8
    let stencil = try makeIntermediateTexture(descriptor)
    return Scratch(mask: mask, multisample: multisample, stencil: stencil, blurred: mask, horizontal: mask)
  }

  private static func tile(path: CGPath, sigma: Double, scale: SIMD2<Float>, width: Int, height: Int,
                           bounded: Bool = true, sourceBounds: CGRect? = nil,
                           sourceClip: CGRect? = nil) -> Tile? {
    let scaledSigma = Self.impellerScaleSigma(Float(sigma))
    let physicalSigma = scaledSigma * scale
    let sourceRadius = simd_max((physicalSigma - SIMD2(repeating: 0.5)) * Float(3).squareRoot(), .zero)
    let padding = Double(max(sourceRadius.x, sourceRadius.y) + 2)
    let bounds = path.boundingBoxOfPath
    guard !bounds.isEmpty, !bounds.isNull, !bounds.isInfinite else { return nil }
    if sigma > 0 {
      // Contents::RenderToSnapshot retains a fractional coverage origin and a
      // one-pixel border. Gaussian then adds symmetric divisible padding; it
      // does not snap this coordinate system to the global pixel grid.
      let geometry = sourceBounds ?? path.boundingBox
      var source = CGRect(x: geometry.minX * Double(scale.x) - 1,
        y: geometry.minY * Double(scale.y) - 1,
        width: geometry.width * Double(scale.x) + 2,
        height: geometry.height * Double(scale.y) + 2)
      // A gradient mask is nested inside SrcIn. Its Gaussian input inherits
      // the outer entity's viewport hint (ContentsFilterInput::GetSnapshot),
      // rather than the expanded hint of a directly rendered solid blur.
      if let sourceClip { source = source.intersection(sourceClip) }
      guard !source.isNull, source.width > 0, source.height > 0 else { return nil }
      source.size = CGSize(width: ceil(source.width), height: ceil(source.height))
      let factor = min(Self.impellerBlurScale(physicalSigma.x), Self.impellerBlurScale(physicalSigma.y))
      let divisor = Double(1 / factor)
      let padX = ceil(Double(sourceRadius.x)), padY = ceil(Double(sourceRadius.y))
      let outWidth = ceil((source.width + padX * 2) / divisor) * divisor
      let outHeight = ceil((source.height + padY * 2) / divisor) * divisor
      let full = CGRect(x: source.minX - (outWidth - source.width) / 2,
        y: source.minY - (outHeight - source.height) / 2, width: outWidth, height: outHeight)
      let needed = bounded ? full.intersection(CGRect(x: -padX - divisor, y: -padY - divisor,
        width: Double(width) + 2 * (padX + divisor), height: Double(height) + 2 * (padY + divisor))) : full
      guard !needed.isNull, needed.width > 0, needed.height > 0 else { return nil }
      let firstX = floor((needed.minX - full.minX) / divisor), firstY = floor((needed.minY - full.minY) / divisor)
      let lastX = ceil((needed.maxX - full.minX) / divisor), lastY = ceil((needed.maxY - full.minY) / divisor)
      let region = CGRect(x: full.minX + firstX * divisor, y: full.minY + firstY * divisor,
        width: (lastX - firstX) * divisor, height: (lastY - firstY) * divisor)
      let sourceNeeded = source.intersection(region.insetBy(dx: -padX - 2, dy: -padY - 2))
      let sx = floor(sourceNeeded.minX - source.minX), sy = floor(sourceNeeded.minY - source.minY)
      let sourceRegion = CGRect(x: source.minX + sx, y: source.minY + sy,
        width: ceil(sourceNeeded.maxX - source.minX) - sx,
        height: ceil(sourceNeeded.maxY - source.minY) - sy)
      var tile = Tile(path: path, region: region, sigma: physicalSigma * factor,
        radii: SIMD2(Int(round(sourceRadius.x * factor)), Int(round(sourceRadius.y * factor))), filterScale: factor)
      tile.sourceRegion = sourceRegion
      return tile
    }
    let raw = CGRect(x: floor(bounds.minX * Double(scale.x) - padding),
                     y: floor(bounds.minY * Double(scale.y) - padding),
                     width: ceil(bounds.width * Double(scale.x) + padding * 2 + 2),
                     height: ceil(bounds.height * Double(scale.y) + padding * 2 + 2))
    let region = bounded ? raw.intersection(CGRect(x: -padding, y: -padding,
                                        width: Double(width) + padding * 2, height: Double(height) + padding * 2)).integral : raw.integral
    guard !region.isNull, region.width > 0, region.height > 0 else { return nil }
    let factor = min(Self.impellerBlurScale(physicalSigma.x), Self.impellerBlurScale(physicalSigma.y))
    let divisor = Double(1 / factor)
    let aligned = CGRect(x: floor(region.minX / divisor) * divisor, y: floor(region.minY / divisor) * divisor,
                         width: ceil((region.maxX - floor(region.minX / divisor) * divisor) / divisor) * divisor,
                         height: ceil((region.maxY - floor(region.minY / divisor) * divisor) / divisor) * divisor)
    return Tile(path: path, region: aligned, sigma: physicalSigma * factor,
                radii: SIMD2(Int(round(sourceRadius.x * factor)), Int(round(sourceRadius.y * factor))),
                filterScale: factor)
  }

  private static func pack(_ tiles: inout [Tile], pageLimit: Int = 8192) -> [SIMD2<Int>] {
    guard !tiles.isEmpty else { return [] }
    let widest = tiles.map { $0.rasterWidth + 4 }.max()!
    let pageWidth = max(1024, Int(pow(2, ceil(log2(Double(widest))))))
    let pageHeight = max(pageLimit, tiles.map { $0.rasterHeight + 4 }.max()!)
    var pages: [SIMD2<Int>] = []
    var x = 2, y = 2, rowHeight = 0, page = 0
    // A stable shelf order preserves the authored draw order separately, while
    // all independent coverage masks are built together before compositing.
    for index in tiles.indices {
      let width = tiles[index].rasterWidth, height = tiles[index].rasterHeight
      if x + width + 2 > pageWidth { x = 2; y += rowHeight + 4; rowHeight = 0 }
      if y + height + 2 > pageHeight {
        pages.append(SIMD2(pageWidth, ((y + rowHeight + 2 + 127) / 128) * 128)); page += 1
        x = 2; y = 2; rowHeight = 0
      }
      tiles[index].page = page; tiles[index].origin = SIMD2(x, y)
      x += width + 4; rowHeight = max(rowHeight, height)
    }
    pages.append(SIMD2(pageWidth, ((y + rowHeight + 2 + 127) / 128) * 128))
    return pages
  }

  private func encodeCoverage(tiles: [Tile], atlas: Scratch, scale: SIMD2<Float>, command: MTLCommandBuffer) throws {
    var vertices: [SIMD2<Float>] = []
    for tile in tiles {
      let scale = tile.sourceScale ?? scale
      let logical = Self.triangles(path: tile.path, tolerance: 0.08 / Double(max(scale.x, scale.y)))
      let transformed = logical.map { point in
        (point * scale - SIMD2(Float(tile.region.minX), Float(tile.region.minY))) * tile.filterScale
          + SIMD2(Float(tile.origin.x), Float(tile.origin.y))
      }
      let clip = CGRect(x: tile.origin.x, y: tile.origin.y, width: tile.rasterWidth, height: tile.rasterHeight)
      let minimum = SIMD2(Float(clip.minX), Float(clip.minY))
      let maximum = SIMD2(Float(clip.maxX), Float(clip.maxY))
      for triangle in stride(from: 0, to: transformed.count, by: 3) {
        let a = transformed[triangle], b = transformed[triangle + 1], c = transformed[triangle + 2]
        if all(a .>= minimum), all(a .<= maximum), all(b .>= minimum), all(b .<= maximum),
           all(c .>= minimum), all(c .<= maximum) {
          vertices.append(a); vertices.append(b); vertices.append(c)
        } else {
          vertices.append(contentsOf: Self.clipTriangle([a, b, c], to: clip))
        }
      }
    }
    let buffer = vertices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    guard let buffer else { throw Failure("vector_vertex_buffer") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = atlas.multisample
    pass.colorAttachments[0].resolveTexture = atlas.mask
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    pass.colorAttachments[0].storeAction = .multisampleResolve
    pass.stencilAttachment.texture = atlas.stencil
    pass.stencilAttachment.loadAction = .clear
    pass.stencilAttachment.storeAction = .dontCare
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Failure("vector_mask_encoder") }
    var transform = SIMD4<Float>(0, 0, Float(atlas.blurred.width), Float(atlas.blurred.height))
    encoder.setRenderPipelineState(windingPipeline)
    encoder.setDepthStencilState(windingState)
    encoder.setStencilReferenceValue(0)
    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
    encoder.setVertexBytes(&transform, length: 16, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    encoder.setRenderPipelineState(maskPipeline)
    encoder.setDepthStencilState(maskState)
    let paints = tiles.map { tile in TilePaint(
      region: SIMD4(Float(tile.origin.x), Float(tile.origin.y), Float(tile.rasterWidth), Float(tile.rasterHeight)),
      color: tile.color) }
    let paintBuffer = paints.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    guard let paintBuffer else { throw Failure("vector_mask_paints") }
    encoder.setVertexBuffer(paintBuffer, offset: 0, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tiles.count * 6)
    encoder.endEncoding()
  }

  private func encodeDownsample(sources: [Tile], targets: [Tile], source: MTLTexture,
                                destination: MTLTexture, command: MTLCommandBuffer) throws {
    var cells: [Cell] = []
    var pixelCount: UInt32 = 0
    for tile in sources {
      let target = targets[tile.identifier]
      cells.append(Cell(
        placement: SIMD4(UInt32(tile.origin.x), UInt32(tile.origin.y), UInt32(tile.rasterWidth), UInt32(tile.rasterHeight)),
        address: SIMD4(UInt32(target.origin.x), UInt32(target.origin.y), UInt32(target.rasterWidth), UInt32(target.rasterHeight)),
        radii: SIMD4(pixelCount, UInt32(round(1 / target.filterScale)), 0, 0),
        sampling: SIMD4(Float(target.region.minX - tile.region.minX), Float(target.region.minY - tile.region.minY), 0, 0)
      ))
      pixelCount += UInt32(target.rasterWidth * target.rasterHeight)
    }
    let buffer = cells.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    guard let buffer, let encoder = command.makeComputeCommandEncoder() else { throw Failure("vector_downsample_encoder") }
    encoder.setComputePipelineState(downsamplePipeline)
    encoder.setTexture(source, index: 0); encoder.setTexture(destination, index: 1)
    encoder.setSamplerState(sampler, index: 0)
    encoder.setBuffer(buffer, offset: 0, index: 0)
    var count = UInt32(cells.count)
    encoder.setBytes(&count, length: 4, index: 1)
    encoder.dispatchThreads(MTLSize(width: Int(pixelCount), height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    encoder.endEncoding()
  }

  private func encodeBlur(tiles: [Tile], atlas: Scratch, command: MTLCommandBuffer) throws {
    var cells: [Cell] = []
    var weights: [Float] = []
    var pixelCount: UInt32 = 0
    func kernel(_ sigma: Float, _ sourceRadius: Int) -> (UInt32, UInt32) {
      let offset = UInt32(weights.count)
      if sigma <= 0.0001 { weights.append(contentsOf: [0, 1]); return (offset, 1) }
      let radius = sourceRadius >= 16 ? sourceRadius - 1 : sourceRadius
      var values = (-radius...radius).map { exp(-0.5 * Float($0 * $0) / (sigma * sigma)) }
      let total = values.reduce(0, +)
      for index in values.indices { values[index] /= total }
      // Flutter LerpHackKernelSamples: pair adjacent samples, except for the
      // middle sample. Its fragment shader multiplies/accumulates in half.
      let count = radius + 1, middle = count / 2
      var sample = 0
      for index in 0..<count {
        if index == middle {
          weights.append(contentsOf: [Float(sample - radius), values[sample]])
          sample += 1
        } else {
          let left = values[sample], right = values[sample + 1], coefficient = left + right
          let position = (Float(sample - radius) * left + Float(sample + 1 - radius) * right) / coefficient
          weights.append(contentsOf: [position, coefficient]); sample += 2
        }
      }
      return (offset, UInt32(count))
    }
    for tile in tiles {
      let (offsetX, radiusX) = kernel(tile.sigma.x, tile.radii.x), (offsetY, radiusY) = kernel(tile.sigma.y, tile.radii.y)
      cells.append(Cell(placement: SIMD4(UInt32(tile.origin.x), UInt32(tile.origin.y), UInt32(tile.rasterWidth), UInt32(tile.rasterHeight)),
                        address: SIMD4(pixelCount, offsetX, offsetY, 0), radii: SIMD4(radiusX, radiusY, 0, 0)))
      pixelCount += UInt32(tile.rasterWidth * tile.rasterHeight)
    }
    let cellBuffer = cells.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    let weightBuffer = weights.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    guard let cellBuffer, let weightBuffer else { throw Failure("vector_atlas_buffers") }
    // The installed Impeller evaluates Y, then X (quantization is observable).
    for horizontal in [false, true] {
      guard let encoder = command.makeComputeCommandEncoder() else { throw Failure("vector_blur_encoder") }
      encoder.setComputePipelineState(horizontal ? horizontalBlur : verticalBlur)
      encoder.setTexture(horizontal ? atlas.horizontal : atlas.mask, index: 0)
      encoder.setTexture(horizontal ? atlas.blurred : atlas.horizontal, index: 1)
      encoder.setBuffer(cellBuffer, offset: 0, index: 0)
      encoder.setBuffer(weightBuffer, offset: 0, index: 1)
      var count = UInt32(cells.count)
      encoder.setBytes(&count, length: 4, index: 2)
      encoder.dispatchThreads(MTLSize(width: Int(pixelCount), height: 1, depth: 1),
                              threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
      encoder.endEncoding()
    }
  }

  private static func clipTriangle(_ triangle: [SIMD2<Float>], to rect: CGRect) -> [SIMD2<Float>] {
    let limits: [(Int, Float, Bool)] = [(0, Float(rect.minX), true), (0, Float(rect.maxX), false),
                                       (1, Float(rect.minY), true), (1, Float(rect.maxY), false)]
    var polygon = triangle
    for (axis, limit, minimum) in limits {
      if polygon.isEmpty { return [] }
      var clipped: [SIMD2<Float>] = []
      var previous = polygon.last!
      var previousInside = minimum ? previous[axis] >= limit : previous[axis] <= limit
      for point in polygon {
        let inside = minimum ? point[axis] >= limit : point[axis] <= limit
        if inside != previousInside {
          let t = (limit - previous[axis]) / (point[axis] - previous[axis])
          clipped.append(previous + (point - previous) * t)
        }
        if inside { clipped.append(point) }
        previous = point; previousInside = inside
      }
      polygon = clipped
    }
    guard polygon.count >= 3 else { return [] }
    return (1..<(polygon.count - 1)).flatMap { [polygon[0], polygon[$0], polygon[$0 + 1]] }
  }

  // Exact sigma adjustment used by the installed Flutter SDK's Impeller.
  static func impellerScaleSigma(_ sigma: Float) -> Float {
    let clamped = min(sigma, 500)
    return clamped * (1 - 0.0034 * clamped + 0.0000034 * clamped * clamped)
  }
  static func impellerBlurScale(_ sigma: Float) -> Float {
    if sigma <= 4 { return 1 }
    let exponent = max(-4, round(log2(4 / sigma)))
    let result = pow(2, exponent)
    if result < 0.125 {
      let next = pow(2, exponent + 1)
      let radius = max(0, (sigma - 0.5) * 1.7320508075688772)
      if (round(radius * next) * 2 + 1) <= 41 { return next }
    }
    return result
  }

  static func triangles(path: CGPath, tolerance: Double) -> [SIMD2<Float>] {
    var polygons: [[CGPoint]] = []
    var current: [CGPoint] = []
    func flush() { if current.count > 2 { polygons.append(current) }; current.removeAll(keepingCapacity: true) }
    func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
      let dx = b.x - a.x, dy = b.y - a.y
      let length = hypot(dx, dy)
      return length < 1e-12 ? hypot(p.x - a.x, p.y - a.y) : abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
    }
    func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ depth: Int) {
      if depth >= 16 || max(distance(b, a, d), distance(c, a, d)) <= tolerance {
        current.append(d); return
      }
      let ab = midpoint(a, b), bc = midpoint(b, c), cd = midpoint(c, d)
      let abc = midpoint(ab, bc), bcd = midpoint(bc, cd), middle = midpoint(abc, bcd)
      cubic(a, ab, abc, middle, depth + 1); cubic(middle, bcd, cd, d, depth + 1)
    }
    path.applyWithBlock { pointer in
      let element = pointer.pointee
      switch element.type {
      case .moveToPoint: flush(); current.append(element.points[0])
      case .addLineToPoint: current.append(element.points[0])
      case .addQuadCurveToPoint:
        let a = current.last ?? .zero, b = element.points[0], c = element.points[1]
        cubic(a, CGPoint(x: a.x + (b.x - a.x) * 2 / 3, y: a.y + (b.y - a.y) * 2 / 3),
              CGPoint(x: c.x + (b.x - c.x) * 2 / 3, y: c.y + (b.y - c.y) * 2 / 3), c, 0)
      case .addCurveToPoint: cubic(current.last ?? .zero, element.points[0], element.points[1], element.points[2], 0)
      case .closeSubpath: flush()
      @unknown default: preconditionFailure("Unrepresented CGPath element")
      }
    }
    flush()
    var result: [SIMD2<Float>] = []
    for polygon in polygons {
      let origin = polygon[0]
      for index in 1..<(polygon.count - 1) {
        for point in [origin, polygon[index], polygon[index + 1]] {
          result.append(SIMD2(Float(point.x), Float(point.y)))
        }
      }
    }
    return result
  }

  private struct Failure: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }
  private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; };
    struct Params { float4 target, region, clipRegion, startEnd, color, info, maskUV, clipUV, flags;
      float4 blurCenterAdjust, blurRadiusExponent, blurFade, localRowX, localRowY, maskSourceRegion, maskScale, gradientSnapshot; };
    struct ShadowVertex { float4 position [[position]]; half gaussian; };
    vertex ShadowVertex vectorShadowVertex(uint id [[vertex_id]], constant Params& p [[buffer(0)]],
        device const float4* points [[buffer(1)]]) {
      float4 point = points[id];
      return { float4(point.x / p.target.x * 2 - 1, 1 - point.y / p.target.y * 2, 0, 1), half(point.z) };
    }
    fragment half4 vectorShadowFragment(ShadowVertex in [[stage_in]], constant Params& p [[buffer(0)]],
        texture2d<float> clip [[texture(1)]], sampler s [[sampler(0)]]) {
      // Flutter gaussian.glsl: IPHalfFractionToFastGaussianCDF + IPErf.
      half x = in.gaussian * 4.0h - 2.0h;
      half a = abs(x);
      half b = (0.278393h + (0.230389h + 0.078108h * a * a) * a) * a + 1.0h;
      half coverage = (1.0h + sign(x) * (1.0h - 1.0h / (b * b * b * b))) * 0.5h;
      if (p.info.w > 0) {
        float2 position = (in.position.xy - p.clipRegion.xy) / p.clipRegion.zw;
        float2 halfPixel = 0.5f / float2(clip.get_width(), clip.get_height());
        float2 uv = clamp(p.clipUV.xy + position * p.clipUV.zw,
          p.clipUV.xy + halfPixel, p.clipUV.xy + p.clipUV.zw - halfPixel);
        coverage *= half(all(position >= 0) && all(position <= 1) ? clip.sample(s, uv).r : 0);
      }
      return half4(float4(p.color.rgb * p.color.a, p.color.a)) * coverage * half(p.flags.w);
    }
    vertex V vectorPathVertex(uint id [[vertex_id]], constant float2* points [[buffer(0)]],
        constant float4& region [[buffer(1)]]) {
      float2 uv = (points[id] - region.xy) / region.zw;
      return { float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1) };
    }
    vertex V vectorMaskVertex(uint id [[vertex_id]]) {
      const float2 uv[3] = {float2(0,0), float2(2,0), float2(0,2)};
      return { float4(uv[id].x * 2 - 1, 1 - uv[id].y * 2, 0, 1) };
    }
    fragment half4 vectorMaskFragment() { return 1; }
    struct TilePaint { float4 region, color; };
    struct TileVertex { float4 position [[position]]; half4 color [[flat]]; };
    vertex TileVertex vectorTileVertex(uint id [[vertex_id]], constant TilePaint* paints [[buffer(0)]],
        constant float4& target [[buffer(1)]]) {
      const float2 uv[6] = {float2(0,0),float2(1,0),float2(0,1),float2(1,0),float2(1,1),float2(0,1)};
      TilePaint paint = paints[id / 6];
      float2 screen = (paint.region.xy + uv[id % 6] * paint.region.zw) / target.zw;
      return {float4(screen.x * 2 - 1, 1 - screen.y * 2, 0, 1), half4(paint.color)};
    }
    fragment half4 vectorTileFragment(TileVertex in [[stage_in]]) { return in.color; }
    vertex V vectorColorVertex(uint id [[vertex_id]], constant Params& p [[buffer(0)]]) {
      const float2 uv[6] = {float2(0,0), float2(1,0), float2(0,1), float2(1,0), float2(1,1), float2(0,1)};
      float2 screen = (p.region.xy + uv[id] * p.region.zw) / p.target.xy;
      return { float4(screen.x * 2 - 1, 1 - screen.y * 2, 0, 1) };
    }
    // Flutter Authors, BSD-3-Clause: impeller/compiler/shader_lib/impeller/rrect.glsl.
    float vectorErf7(float x) {
      x *= 2.0f / sqrt(3.1415926f);
      float xx = x * x;
      x += (0.24295f + (0.03395f + 0.0104f * xx) * xx) * (x * xx);
      return x / sqrt(1.0f + x * x);
    }
    float4 vectorPaint(float2 pixel, float2 ditherPixel, constant Params& p,
        constant float4* colors, constant float* stops) {
      float4 color = p.color;
      if (p.info.x > 0) {
        float3 world = float3(pixel / p.target.zw, 1);
        float2 point = float2(dot(world, p.localRowX.xyz), dot(world, p.localRowY.xyz));
        float2 delta = p.startEnd.zw - p.startEnd.xy;
        float2 sweepCoord = point - p.startEnd.xy;
        float t = p.info.x > 2.5 ? atan2(-sweepCoord.y, -sweepCoord.x) * (1.0f / (2.0f * M_PI_F)) + 0.5f
          : p.info.x > 1.5 ? length(point - p.startEnd.xy) / p.info.z
          : dot(point - p.startEnd.xy, delta) / max(dot(delta, delta), 1e-12f);
        t = clamp(t, 0.0f, 1.0f);
        color = t <= stops[0] ? colors[0] : colors[int(p.info.y) - 1];
        for (int i = 1; i < int(p.info.y); ++i) {
          if (t >= stops[i-1] && t <= stops[i]) {
            float inverseDelta = 1.0f / max(stops[i] - stops[i-1], 1e-12f);
            color = inverseDelta > 1000 ? colors[i] : mix(colors[i-1], colors[i], (t - stops[i-1]) * inverseDelta);
            break;
          }
        }
      }
      float opacity = p.info.x > 0 ? p.color.a : 1.0f;
      float4 result = float4(color.rgb * color.a, color.a) * opacity * p.flags.w;
      if (p.info.x > 0) {
        // Impeller dithering.glsl, applied after premultiplication and opacity.
        uint x = uint(ditherPixel.x) % 8;
        uint y = uint(ditherPixel.y) ^ x;
        uint m = (y & 1) << 5 | (x & 1) << 4 | (y & 2) << 2 |
                 (x & 2) << 1 | (y & 4) >> 1 | (x & 4) >> 2;
        float dither = float(m) * (2.0f / 128.0f) - (63.0f / 128.0f);
        result.rgb += dither * (1.0f / 64.0f);
      }
      return result;
    }
    fragment float4 vectorColorFragment(V in [[stage_in]], constant Params& p [[buffer(0)]],
        constant float4* colors [[buffer(1)]], constant float* stops [[buffer(2)]],
        texture2d<float> mask [[texture(0)]], texture2d<float> clip [[texture(1)]], sampler s [[sampler(0)]]) {
      float2 pixel = in.position.xy / p.flags.x;
      float3 world = float3(pixel / p.target.zw, 1);
      float2 local = float2(dot(world, p.localRowX.xyz), dot(world, p.localRowY.xyz));
      float2 maskPixel = p.maskScale.z > 0 ? local * p.maskScale.xy : pixel;
      float2 maskPosition = (maskPixel - p.maskSourceRegion.xy) / p.maskSourceRegion.zw;
      float2 maskHalfPixel = 0.5f / float2(mask.get_width(), mask.get_height());
      float2 maskSample = clamp(p.maskUV.xy + maskPosition * p.maskUV.zw,
        p.maskUV.xy + maskHalfPixel, p.maskUV.xy + p.maskUV.zw - maskHalfPixel);
      float4 filtered = all(maskPosition >= 0) && all(maskPosition <= 1) ? mask.sample(s, maskSample) : float4(0);
      float coverage = p.flags.y > 0 ? 1.0f : filtered.a;
      if (p.flags.z > 1.5f) {
        // Flutter circle.frag: local-space SDF with a one-physical-pixel fade.
        float2 vectorToCenter = pixel / p.target.zw - p.blurCenterAdjust.xy;
        float distanceToCenter = length(vectorToCenter);
        float2 unit = distanceToCenter > 0 ? vectorToCenter / distanceToCenter : float2(1, 0);
        float localDistance = dot(1.0f / p.target.zw, abs(unit));
        float fade = localDistance * 0.5f;
        coverage = 1.0f - smoothstep(-fade, fade, distanceToCenter - p.blurRadiusExponent.x);
      } else if (p.flags.z > 0) {
        float2 adjusted = abs(pixel / p.target.zw - p.blurCenterAdjust.xy) - p.blurCenterAdjust.zw;
        float2 positive = max(adjusted, 0.0f);
        float dPos = pow(pow(positive.x, p.blurRadiusExponent.y) + pow(positive.y, p.blurRadiusExponent.y), p.blurRadiusExponent.z);
        float d = dPos + min(max(adjusted.x, adjusted.y), 0.0f) - p.blurRadiusExponent.x;
        coverage = float(half(p.blurFade.z * (vectorErf7(p.blurFade.x * (p.blurFade.y + d)) - vectorErf7(p.blurFade.x * d))));
      }
      if (p.info.w > 0) {
        float2 clipPosition = (pixel - p.clipRegion.xy) / p.clipRegion.zw;
        float2 clipHalfPixel = 0.5f / float2(clip.get_width(), clip.get_height());
        float2 clipSample = clamp(p.clipUV.xy + clipPosition * p.clipUV.zw,
          p.clipUV.xy + clipHalfPixel, p.clipUV.xy + p.clipUV.zw - clipHalfPixel);
        coverage *= all(clipPosition >= 0) && all(clipPosition <= 1) ? clip.sample(s, clipSample).r : 0;
      }
      if (p.maskScale.w > 1.5) return filtered * (filtered.a > 0 ? coverage / filtered.a : 0);
      float4 result = vectorPaint(pixel, pixel, p, colors, stops);
      if (p.maskScale.w > 0 && p.maskScale.w < 1.5) {
        // Reproduce the linear-sampled offscreen gradient, including its own
        // Bayer pixel origin. Screen-aligned dither accumulates coherently across
        // additive layers and changes the original painter's texture.
        float2 coordinate = pixel - p.gradientSnapshot.xy - 0.5f;
        float2 base = floor(coordinate), fraction = fract(coordinate);
        float4 taps[4];
        for (uint i = 0; i < 4; ++i) {
          float2 uv = clamp(base + float2(i & 1, i >> 1), float2(0), p.gradientSnapshot.zw - 1);
          float4 tap = vectorPaint(p.gradientSnapshot.xy + uv + 0.5f, uv + 0.5f, p, colors, stops);
          taps[i] = rint(clamp(tap, 0.0f, 1.0f) * 255.0f) / 255.0f;
        }
        result = mix(mix(taps[0], taps[1], fraction.x), mix(taps[2], taps[3], fraction.x), fraction.y);
      }
      // Impeller mask-filter color sources first snapshot their premultiplied
      // gradient into the default 8-bit offscreen, then apply SrcIn into another
      // 8-bit target. Preserve those two quantizations before destination blend.
      if (p.maskScale.w > 0) result = rint(clamp(result, 0.0f, 1.0f) * 255.0f) / 255.0f;
      result *= coverage;
      if (p.maskScale.w > 0) result = rint(clamp(result, 0.0f, 1.0f) * 255.0f) / 255.0f;
      return result;
    }
    struct Cell { uint4 placement, address, radii; float4 sampling; };
    inline float4 blurValue(uint index, bool horizontal, texture2d<float, access::read> input,
        device const Cell* cells, device const float* weights, uint count,
        thread uint2& destination) {
      uint lo = 0, hi = count;
      while (lo + 1 < hi) { uint mid = (lo + hi) / 2; if (cells[mid].address.x <= index) lo = mid; else hi = mid; }
      Cell cell = cells[lo];
      uint local = index - cell.address.x;
      int2 point = int2(local % cell.placement.z, local / cell.placement.z);
      destination = cell.placement.xy + uint2(point);
      int samples = int(horizontal ? cell.radii.x : cell.radii.y);
      uint offset = horizontal ? cell.address.y : cell.address.z;
      half4 result = 0;
      for (int sample = 0; sample < samples; ++sample) {
        float position = weights[offset + uint(sample) * 2];
        float coefficient = weights[offset + uint(sample) * 2 + 1];
        int lower = int(floor(position)); float fraction = position - float(lower);
        int2 a = point + (horizontal ? int2(lower,0) : int2(0,lower));
        int2 b = a + (horizontal ? int2(1,0) : int2(0,1));
        float4 left = all(a >= 0) && all(a < int2(cell.placement.zw)) ? input.read(cell.placement.xy + uint2(a)) : float4(0);
        float4 right = all(b >= 0) && all(b < int2(cell.placement.zw)) ? input.read(cell.placement.xy + uint2(b)) : float4(0);
        result += half(coefficient) * half4(mix(left, right, fraction));
      }
      return float4(result);
    }
    kernel void vectorBlurHorizontal(uint index [[thread_position_in_grid]],
        texture2d<float, access::read> input [[texture(0)]], texture2d<float, access::write> output [[texture(1)]],
        device const Cell* cells [[buffer(0)]], device const float* weights [[buffer(1)]], constant uint& count [[buffer(2)]]) {
      uint2 destination;
      float4 value = blurValue(index, true, input, cells, weights, count, destination);
      output.write(value, destination);
    }
    float4 vectorAtlasDecal(texture2d<float> input, sampler s, float2 point,
        float2 minimum, float2 maximum, float2 dimensions) {
      float2 coverage = clamp(point - minimum + 1, 0.0f, 1.0f) * clamp(maximum - point + 1, 0.0f, 1.0f);
      return input.sample(s, clamp(point, minimum, maximum) / dimensions) * coverage.x * coverage.y;
    }
    kernel void vectorDownsample(uint index [[thread_position_in_grid]],
        texture2d<float> input [[texture(0)]], texture2d<float, access::write> output [[texture(1)]],
        sampler s [[sampler(0)]], device const Cell* cells [[buffer(0)]], constant uint& count [[buffer(1)]]) {
      uint lo = 0, hi = count;
      while (lo + 1 < hi) { uint mid = (lo + hi) / 2; if (cells[mid].radii.x <= index) lo = mid; else hi = mid; }
      Cell cell = cells[lo];
      uint local = index - cell.radii.x;
      uint2 point = uint2(local % cell.address.z, local / cell.address.z);
      float divisor = float(cell.radii.y);
      float2 center = float2(cell.placement.xy) + cell.sampling.xy + (float2(point) + 0.5f) * divisor;
      float2 dimensions = float2(input.get_width(), input.get_height());
      float2 minimum = float2(cell.placement.xy) + 0.5f;
      float2 maximum = float2(cell.placement.xy + cell.placement.zw) - 0.5f;
      float4 total = 0;
      if (divisor <= 2) total = vectorAtlasDecal(input, s, center, minimum, maximum, dimensions);
      else {
        float edge = divisor * 0.5f - 1;
        float ratio = 4 / (divisor * divisor);
        for (float y = -edge; y <= edge; y += 2)
          for (float x = -edge; x <= edge; x += 2)
            total += vectorAtlasDecal(input, s, center + float2(x,y), minimum, maximum, dimensions) * ratio;
      }
      output.write(total, cell.address.xy + point);
    }
    kernel void vectorBlurVertical(uint index [[thread_position_in_grid]],
        texture2d<float, access::read> input [[texture(0)]], texture2d<float, access::write> output [[texture(1)]],
        device const Cell* cells [[buffer(0)]], device const float* weights [[buffer(1)]], constant uint& count [[buffer(2)]]) {
      uint2 destination;
      float4 value = blurValue(index, false, input, cells, weights, count, destination);
      output.write(value, destination);
    }
    """
}

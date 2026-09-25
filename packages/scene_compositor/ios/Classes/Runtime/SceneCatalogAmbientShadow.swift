// Derived from Flutter impeller/entity/geometry/shadow_path_geometry.cc,
// path_tessellator.{cc,h}, wangs_formula.cc and tessellator.cc.
// Copyright 2013 The Flutter Authors. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// * Neither the name of Google Inc. nor the names of its contributors may be
//   used to endorse or promote products derived from this software without
//   specific prior written permission.
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

import CoreGraphics
import Foundation

/// Impeller's convex, solid-fill ambient-shadow mesh, not a blur approximation.
/// Input paths remain local; output positions include the complete device CTM.
/// Unsupported contours return nil so the caller can retain its other blur path.
enum SceneCatalogAmbientShadow {
  struct Mesh {
    let positions: [SIMD2<Float>]
    /// Impeller's linear gaussian coefficient: 1 at umbra, 0 at outer penumbra.
    let penumbra: [Float]
    let indices: [UInt16]
  }

  static func makeVertices(
    path: CGPath, transform: CGAffineTransform, deviceRadius: CGFloat
  ) -> Mesh? {
    let values = [transform.a, transform.b, transform.c, transform.d,
                  transform.tx, transform.ty, deviceRadius]
    guard values.allSatisfy({ $0.isFinite }), deviceRadius > 0,
          Float(deviceRadius).isFinite else { return nil }
    let a = Float(transform.a), b = Float(transform.b)
    let c = Float(transform.c), d = Float(transform.d)
    let scale = SIMD2<Float>((a * a + b * b).squareRoot(),
                             (c * c + d * d).squareRoot())
    guard scale.x.isFinite, scale.y.isFinite else { return nil }
    guard scale.x * scale.y > 0 else {
      return Mesh(positions: [], penumbra: [], indices: [])
    }
    guard let points = flatten(path: path, scale: max(scale.x, scale.y)),
          let polygon = accumulate(points, scale: scale) else { return nil }
    guard polygon.points.count >= 3 else {
      return Mesh(positions: [], penumbra: [], indices: [])
    }
    let builder = Builder(points: polygon.points, radius: Float(deviceRadius))
    guard builder.generate(centroid: polygon.centroid, direction: polygon.direction)
    else { return nil }
    let tx = Float(transform.tx), ty = Float(transform.ty)
    let inverse = SIMD2<Float>(1 / scale.x, 1 / scale.y)
    let devicePositions = builder.positions.map { position -> SIMD2<Float> in
      let local = position * inverse
      return SIMD2<Float>(a * local.x + c * local.y + tx,
                          b * local.x + d * local.y + ty)
    }
    guard devicePositions.allSatisfy(finite),
          builder.gaussians.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 })
    else { return nil }
    return Mesh(positions: devicePositions, penumbra: builder.gaussians,
                indices: builder.indices)
  }

  private typealias Point = SIMD2<Float>
  private static func cross(_ a: Point, _ b: Point) -> Float { a.x * b.y - a.y * b.x }
  private static func dot(_ a: Point, _ b: Point) -> Float { a.x * b.x + a.y * b.y }
  private static func lengthSquared(_ a: Point) -> Float { dot(a, a) }
  private static func finite(_ a: Point) -> Bool { a.x.isFinite && a.y.isFinite }
  private static func point(_ p: CGPoint) -> Point { Point(Float(p.x), Float(p.y)) }
  private static func sign(_ value: Float) -> Float { value.sign == .minus ? -1 : 1 }

  // PathPruner + PathFillWriter: implicit fill closure and Wang subdivisions.
  // CGPath has no rational-conic verb; its quadratic/cubic verbs stay unchanged.
  private static func flatten(path: CGPath, scale: Float) -> [Point]? {
    var points: [Point] = []
    var current = Point.zero, origin = Point.zero
    var hasSegments = false, contourEnded = false, invalid = false
    func append(_ p: Point) {
      guard finite(p), points.count < Int(UInt16.max) else { invalid = true; return }
      points.append(p)
    }
    func begin() {
      if !hasSegments {
        if contourEnded { invalid = true }
        append(origin)
        hasSegments = true
      }
    }
    func end() {
      if hasSegments {
        if current != origin { append(origin) }
        contourEnded = true
      }
      current = origin
      hasSegments = false
    }
    func line(_ p: Point) {
      begin()
      if p != current { append(p); current = p }
    }
    path.applyWithBlock { elementPointer in
      guard !invalid else { return }
      let element = elementPointer.pointee
      switch element.type {
      case .moveToPoint:
        end()
        origin = point(element.points[0]); current = origin
        if !finite(origin) { invalid = true }
      case .addLineToPoint:
        line(point(element.points[0]))
      case .addQuadCurveToPoint:
        let cp = point(element.points[0]), p2 = point(element.points[1])
        guard finite(cp), finite(p2) else { invalid = true; return }
        if cp == current || cp == p2 { line(p2); return }
        begin()
        let curvature = current - cp * 2 + p2
        let divisions = ceilf((scale * lengthSquared(curvature).squareRoot()).squareRoot())
        guard divisions.isFinite, divisions < Float(UInt16.max) else { invalid = true; return }
        if divisions > 1 {
          for i in 1..<Int(divisions) {
            let t = Float(i) / divisions, u: Float = 1 - t
            append(current * u * u + 2 * cp * u * t + p2 * t * t)
          }
        }
        append(p2); current = p2
      case .addCurveToPoint:
        let cp1 = point(element.points[0]), cp2 = point(element.points[1])
        let p2 = point(element.points[2])
        guard finite(cp1), finite(cp2), finite(p2) else { invalid = true; return }
        begin()
        if cp1 == current && cp2 == current && p2 == current { return }
        let aa = current - cp1 * 2 + cp2, bb = cp1 - cp2 * 2 + p2
        let k = scale * 0.75 * 4
        let divisions = ceilf((k * max(lengthSquared(aa), lengthSquared(bb)).squareRoot()).squareRoot())
        guard divisions.isFinite, divisions < Float(UInt16.max) else { invalid = true; return }
        if divisions > 1 {
          for i in 1..<Int(divisions) {
            let t = Float(i) / divisions, u: Float = 1 - t
            append(current * u * u * u + 3 * cp1 * u * u * t +
                   3 * cp2 * u * t * t + p2 * t * t * t)
          }
        }
        append(p2); current = p2
      case .closeSubpath:
        begin(); end()
      @unknown default:
        invalid = true
      }
    }
    end()
    return invalid ? nil : points
  }

  private struct Polygon {
    var points: [Point]
    var centroid = Point.zero
    var direction: Float = 0
  }

  private static func accumulate(_ input: [Point], scale: Point) -> Polygon? {
    var points: [Point] = []
    let deviceScale = scale * 16
    for source in input {
      let p = source * deviceScale
      let value = Point(p.x.rounded(.toNearestOrAwayFromZero),
                        p.y.rounded(.toNearestOrAwayFromZero)) * (1.0 / 16)
      guard finite(value) else { return nil }
      if let previous = points.last {
        if value == previous { continue }
        if points.count >= 2 {
          let before = points[points.count - 2]
          if cross(previous - before, value - before) == 0 {
            points.removeLast()
            if value == before { continue }
          }
        }
      }
      points.append(value)
    }
    if !points.isEmpty { points.removeLast() } // closing vertex, EndContour
    guard points.count >= 3 else { return Polygon(points: []) }
    var previous = points[points.count - 1], before = points[points.count - 2]
    let first = points[0]
    var centroid = Point.zero
    var direction: Float = 0, area: Float = 0
    var axisDirection = Point.zero
    var axisChanges = SIMD2<Int>(repeating: 0)
    for p in points {
      let delta = p - previous
      for axis in 0..<2 {
        if axisDirection[axis] == 0 || axisDirection[axis] * delta[axis] < 0 {
          axisDirection[axis] = sign(delta[axis]); axisChanges[axis] += 1
        }
        if axisChanges[axis] > 3 { return nil }
      }
      if direction != 0 && cross(previous - before, p - before) * direction < 0 {
        return nil
      }
      let v0 = previous - first, v1 = p - first
      let quadArea = cross(v0, v1)
      if quadArea != 0 {
        if direction == 0 { direction = sign(quadArea) }
        else if quadArea * direction < 0 { return nil }
        centroid += (v0 + v1) * quadArea
        area += quadArea
      }
      before = previous; previous = p
    }
    if direction == 0 { return Polygon(points: []) }
    centroid /= 3 * area
    guard finite(centroid) else { return nil }
    return Polygon(points: points, centroid: first + centroid, direction: direction)
  }

  private struct Pin {
    let path: Point
    var delta = Point.zero
    var penumbra = Point.zero
    var tip = Point.zero
    var umbra = Point.zero
    var index: UInt16 = 0
    var fraction: Float = -1
    var previous = 0
    var next = 0
  }

  private final class Builder {
    var pins: [Pin]
    let radius: Float
    var gaussian: Float = 1
    var positions: [Point] = []
    var gaussians: [Float] = []
    var indices: [UInt16] = []
    var overflow = false
    init(points: [Point], radius: Float) {
      pins = points.map { Pin(path: $0) }; self.radius = radius
    }

    func generate(centroid: Point, direction: Float) -> Bool {
      var minimum = radius * radius
      for i in pins.indices {
        let p0 = pins[(i + pins.count - 1) % pins.count].path
        let p1 = pins[i].path
        let u = p1 - p0, v = centroid - p0
        let projection = dot(u, v), length = lengthSquared(u)
        let distance: Float
        if projection <= 0 { distance = lengthSquared(v) }
        else if projection >= length { distance = lengthSquared(centroid - p1) }
        else { let value = cross(u, v); distance = value * value / length }
        minimum = min(minimum, distance)
      }
      var umbra = minimum.squareRoot()
      if umbra < radius + 0.01 {
        umbra -= 0.01
        gaussian = 0.5 * (umbra / radius + 1)
      }
      for i in pins.indices {
        let previous = (i + pins.count - 1) % pins.count
        pins[i].previous = previous; pins[previous].next = i
        let delta = pins[i].path - pins[previous].path
        let normalized = delta / lengthSquared(delta).squareRoot()
        let pinDirection = Point(-normalized.y, normalized.x) * direction
        pins[previous].delta = delta
        pins[previous].penumbra = pinDirection * -radius
        pins[previous].tip = pins[previous].path + pinDirection * umbra
        pins[previous].umbra = pins[previous].tip
      }
      guard let head = resolve(direction: direction) else { return false }
      populate(head: head, centroid: centroid)
      let trigs = Self.trigs(radius: radius)
      guard trigs.count >= 2 else { return false }
      var previous = pins.count - 1
      var lastPoint = pins[previous].path + pins[previous].penumbra
      var lastIndex = append(lastPoint, 0)
      for i in pins.indices {
        if pins[previous].index != pins[i].index {
          triangle(lastIndex, pins[previous].index, pins[i].index)
        }
        var newPoint = pins[i].path + pins[previous].penumbra
        var newIndex = append(newPoint, 0)
        if lastIndex != newIndex { triangle(pins[i].index, lastIndex, newIndex) }
        lastPoint = newPoint; lastIndex = newIndex
        newPoint = pins[i].path + pins[i].penumbra
        newIndex = fan(pin: i, start: lastPoint, end: newPoint,
                       startIndex: lastIndex, trigs: trigs, direction: direction)
        lastPoint = newPoint; lastIndex = newIndex; previous = i
      }
      return !overflow
    }

    private func intersection(_ p0: Pin, _ p1: Pin) -> (Point, Float, Float)? {
      let v0 = p0.delta, v1 = p1.delta, w = p1.tip - p0.tip
      var denominator = cross(v0, v1)
      let positive = denominator > 0
      var numerator0: Float, numerator1: Float
      func outside(_ n: Float, _ d: Float, _ pos: Bool) -> Bool {
        (pos && (n < 0 || n > d)) || (!pos && (n > 0 || n < d))
      }
      func finiteLength(_ v: Point) -> Float { finite(v) ? lengthSquared(v) : -1 }
      if abs(denominator) <= 1.0 / 2048 {
        if abs(cross(w, v0)) > 1.0 / 2048 || abs(cross(w, v1)) > 1.0 / 2048 { return nil }
        let l0 = finiteLength(v0)
        if l0 <= 0 {
          let l1 = finiteLength(v1)
          if l1 <= 0 { return finite(w) && w != .zero ? (p0.tip, 0, 0) : nil }
          numerator1 = dot(v1, -w); denominator = l1
          if outside(numerator1, denominator, true) { return nil }
          numerator0 = 0
        } else {
          numerator0 = dot(v0, w); denominator = l0; numerator1 = 0
          if outside(numerator0, denominator, true) {
            let l1 = finiteLength(v1)
            if l1 <= 0 { return nil }
            let old = numerator0
            numerator0 = dot(v0, w + v1); numerator1 = denominator
            if outside(numerator0, denominator, true) {
              if numerator0 * old > 0 { return nil }
              numerator0 = 0; numerator1 = dot(v1, -w); denominator = l1
            }
          }
        }
      } else {
        numerator0 = cross(w, v1)
        if outside(numerator0, denominator, positive) { return nil }
        numerator1 = cross(w, v0)
        if outside(numerator1, denominator, positive) { return nil }
      }
      let f0 = numerator0 / denominator, f1 = numerator1 / denominator
      return (p0.tip + v0 * f0, f0, f1)
    }

    private func remove(_ pin: Int, head: inout Int?) {
      let next = pins[pin].next, previous = pins[pin].previous
      pins[previous].next = next; pins[next].previous = previous
      if head == pin { head = next == pin ? nil : next }
    }
    private func side(_ origin: Point, _ delta: Point, _ p: Point) -> Float {
      let value = cross(delta, p - origin)
      return abs(value) <= 1.0 / 2048 ? 0 : sign(value)
    }
    private func resolve(direction: Float) -> Int? {
      var head: Int? = 0, current = 0, previous = pins[0].previous
      var iterations = pins.count * pins.count + 1
      while head != nil && previous != current {
        iterations -= 1
        if iterations == 0 { return nil }
        if let (position, f0, f1) = intersection(pins[previous], pins[current]) {
          if f0 < pins[previous].fraction {
            remove(previous, head: &head); previous = pins[previous].previous
          } else if pins[current].fraction > -1 &&
                      lengthSquared(pins[current].umbra - position) < 1.0e-6 {
            break
          } else {
            pins[current].umbra = position; pins[current].fraction = f1
            previous = current; current = pins[current].next
          }
        } else {
          let firstSide = direction * side(pins[current].tip, pins[current].delta, pins[previous].tip)
          if firstSide < 0 && firstSide == direction * side(
            pins[current].tip, pins[current].delta, pins[previous].tip + pins[previous].delta
          ) {
            remove(previous, head: &head); previous = pins[previous].previous
          } else {
            remove(current, head: &head); current = pins[current].next
          }
        }
      }
      guard let start = head else { return nil }
      previous = start; current = pins[start].next
      var count = 1
      while current != start {
        if lengthSquared(pins[previous].umbra - pins[current].umbra) < 1.0 / 256 {
          remove(current, head: &head); current = pins[current].next
        } else {
          count += 1; previous = current; current = pins[current].next
        }
      }
      return count < 3 ? nil : head
    }

    private func populate(head: Int, centroid: Point) {
      var lastIndex = append(centroid, gaussian)
      var next = head, current = pins[head].previous
      for i in pins.indices {
        if next == i || lengthSquared(pins[i].path - pins[current].umbra) >
                         lengthSquared(pins[i].path - pins[next].umbra) {
          current = next; next = pins[next].next
          let index = append(pins[current].umbra, gaussian)
          pins[current].index = index
          if lastIndex != 0 { triangle(0, lastIndex, index) }
          lastIndex = index
        }
        if current != i {
          pins[i].umbra = pins[current].umbra; pins[i].index = lastIndex
        }
      }
      if lastIndex != pins[0].index { triangle(0, lastIndex, pins[0].index) }
    }

    private static func trigs(radius: Float) -> [SIMD2<Double>] {
      // The engine's table uses ceil(radius) for radii below 1024.
      let indexedRadius = ceil(Double(radius))
      let r = indexedRadius < 1024 ? indexedRadius : Double(radius)
      let toleranceRatio = indexedRadius < 1024 ? Double(Float(0.1)) / r : Double(Float(0.1) / radius)
      // Use the engine's rounded Float constants; Swift Float.pi rounds down
      // by one ULP instead of matching the C++ float literal.
      let piOver4: Float = 0.78539816339744830962
      let piOver2: Float = 1.57079632679489661923
      let divisionsValue = ceil(Double(piOver4) / acos(1 - toleranceRatio))
      guard divisionsValue.isFinite, divisionsValue >= 1,
            divisionsValue < Double(UInt16.max) else { return [] }
      let divisions = Int(divisionsValue)
      let angleScale = Double(piOver2 / Float(divisions))
      var values = [SIMD2<Double>(1, 0)]
      if divisions > 1 {
        for i in 1..<divisions {
          let angle = Float(Double(i) * angleScale)
          values.append(SIMD2<Double>(Double(cosf(angle)), Double(sinf(angle))))
        }
      }
      values.append(SIMD2<Double>(0, 1))
      return values
    }

    private func fan(pin: Int, start: Point, end: Point, startIndex: UInt16,
                     trigs: [SIMD2<Double>], direction: Float) -> UInt16 {
      let center = pins[pin].path, centerIndex = pins[pin].index
      var previousIndex = startIndex
      var startDelta = start - center
      let endDelta = end - center
      var i = 1, iterations = 0
      while i < trigs.count {
        iterations += 1
        if iterations > trigs.count * 4 { overflow = true; break }
        let trig = trigs[i], sine = direction >= 0 ? trig.y : -trig.y
        let delta = Point(Float(Double(startDelta.x) * trig.x - Double(startDelta.y) * sine),
                          Float(Double(startDelta.x) * sine + Double(startDelta.y) * trig.x))
        if cross(delta, endDelta) * direction <= 0 { break }
        let index = append(center + delta, 0)
        if previousIndex != index { triangle(centerIndex, previousIndex, index); previousIndex = index }
        if i == trigs.count - 1 { i = 0; startDelta = delta }
        i += 1
      }
      let index = append(center + endDelta, 0)
      if previousIndex != index { triangle(centerIndex, previousIndex, index) }
      return index
    }

    private func append(_ position: Point, _ gaussian: Float) -> UInt16 {
      if positions.last == position && gaussians.last == gaussian {
        return UInt16(positions.count - 1)
      }
      guard positions.count < Int(UInt16.max) else { overflow = true; return 0 }
      let index = UInt16(positions.count)
      positions.append(position); gaussians.append(gaussian)
      return index
    }
    private func triangle(_ a: UInt16, _ b: UInt16, _ c: UInt16) {
      indices.append(contentsOf: [a, b, c])
    }
  }
}

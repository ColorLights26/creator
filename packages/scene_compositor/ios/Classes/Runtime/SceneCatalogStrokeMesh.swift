import CoreGraphics
import simd

/// A round-cap, round-join stroke of straight polylines, built as triangles.
///
/// That stroke is exactly the union of one capsule per segment, so its
/// triangles only have to cover the union: the outer arc of every join, a
/// half disc per cap and a quad per segment. Overlaps are harmless because
/// the renderer counts coverage (clamped) for these meshes instead of winding.
/// This replaces the Core Graphics outline and its curve flattening, which
/// dominate visuals that stroke hundreds of trails every frame.
struct SceneCatalogStrokeMesh {
  private struct Subpath {
    let range: Range<Int>
    let closed: Bool
  }
  /// Path elements land here; CGPath.apply borrows it without a closure.
  private struct Reader {
    var points: [SIMD2<Double>] = []
    var subpaths: [Subpath] = []
    var start = 0, segments = 0
    var curved = false
    var origin = SIMD2<Double>.zero
    mutating func end(closed: Bool) {
      if segments > 0 { subpaths.append(Subpath(range: start..<points.count, closed: closed)) }
      start = points.count; segments = 0
    }
  }
  private var points: [SIMD2<Double>] = []
  private var subpaths: [Subpath] = []
  let halfWidth: Double
  /// Source bounds grown by half the stroke width.
  let bounds: CGRect

  /// Nil when the path has curves or nothing to stroke; those keep the
  /// Core Graphics outline.
  init?(path: CGPath, width: Double) {
    halfWidth = width / 2
    var reader = Reader()
    withUnsafeMutablePointer(to: &reader) { pointer in
      path.apply(info: pointer) { info, element in
        SceneCatalogStrokeMesh.visit(info!.assumingMemoryBound(to: Reader.self), element.pointee)
      }
    }
    reader.end(closed: false)
    guard !reader.curved, !reader.subpaths.isEmpty, halfWidth > 0 else { return nil }
    var low = SIMD2(repeating: Double.infinity), high = -low
    for subpath in reader.subpaths {
      for point in reader.points[subpath.range] { low = simd_min(low, point); high = simd_max(high, point) }
    }
    bounds = CGRect(x: low.x - halfWidth, y: low.y - halfWidth,
                    width: high.x - low.x + 2 * halfWidth, height: high.y - low.y + 2 * halfWidth)
    points = reader.points
    subpaths = reader.subpaths
  }

  private static func visit(_ reader: UnsafeMutablePointer<Reader>, _ element: CGPathElement) {
    switch element.type {
    case .moveToPoint:
      reader.pointee.end(closed: false)
      reader.pointee.origin = SIMD2(Double(element.points[0].x), Double(element.points[0].y))
      reader.pointee.points.append(reader.pointee.origin)
    case .addLineToPoint:
      // After a close, a line starts a new subpath at the closed one's start.
      if reader.pointee.points.count == reader.pointee.start { reader.pointee.points.append(reader.pointee.origin) }
      reader.pointee.points.append(SIMD2(Double(element.points[0].x), Double(element.points[0].y)))
      reader.pointee.segments += 1
    case .closeSubpath:
      reader.pointee.end(closed: true)
    default:
      reader.pointee.curved = true
    }
  }

  /// Appends triangles mapped by [transform] (source to device pixels).
  /// Arcs stay within [tolerance] device pixels of the true circle.
  func appendTriangles(transform t: CGAffineTransform, tolerance: Double,
                       into output: inout [SIMD2<Float>]) {
    let basis = max(hypot(Double(t.a), Double(t.b)), hypot(Double(t.c), Double(t.d)))
    guard basis > 0, basis.isFinite else { return }
    let r = halfWidth, local = tolerance / basis
    let step = local >= r ? Double.pi / 2 : 2 * acos(1 - local / r)
    let cosineStep = cos(step)
    let capCount = Int((Double.pi / step).rounded(.up))
    let capTurn = SIMD2(cos(Double.pi / Double(capCount)), sin(Double.pi / Double(capCount)))
    // Per segment: a quad and usually one join triangle; per subpath: caps.
    output.reserveCapacity(output.count + points.count * 9 + subpaths.count * capCount * 6)
    let a = Double(t.a), b = Double(t.b), c = Double(t.c), d = Double(t.d)
    let tx = Double(t.tx), ty = Double(t.ty)
    func device(_ p: SIMD2<Double>) -> SIMD2<Float> {
      SIMD2(Float(a * p.x + c * p.y + tx), Float(b * p.x + d * p.y + ty))
    }
    /// Fan around [center] from offset [from]: [count] steps of [turn] (cos, sin).
    func fan(_ center: SIMD2<Double>, from: SIMD2<Double>, count: Int, turn: SIMD2<Double>) {
      let hub = device(center)
      var offset = from
      var previous = device(center + offset)
      for _ in 0..<count {
        offset = SIMD2(offset.x * turn.x - offset.y * turn.y, offset.x * turn.y + offset.y * turn.x)
        let next = device(center + offset)
        output.append(hub); output.append(previous); output.append(next)
        previous = next
      }
    }
    func arc(_ center: SIMD2<Double>, from: SIMD2<Double>, sweep: Double) {
      let count = max(1, Int((abs(sweep) / step).rounded(.up)))
      let angle = sweep / Double(count)
      fan(center, from: from, count: count, turn: SIMD2(cos(angle), sin(angle)))
    }
    var vertices: [SIMD2<Double>] = []
    for subpath in subpaths {
      vertices.removeAll(keepingCapacity: true)
      for point in points[subpath.range] where vertices.last.map({ simd_distance_squared($0, point) > 1e-18 }) ?? true {
        vertices.append(point)
      }
      if subpath.closed, vertices.count > 2, simd_distance_squared(vertices[0], vertices[vertices.count - 1]) <= 1e-18 {
        vertices.removeLast()
      }
      if vertices.count == 1 {
        // A zero-length stroke with round caps is a dot.
        fan(vertices[0], from: SIMD2(r, 0), count: capCount * 2, turn: capTurn)
        continue
      }
      let closed = subpath.closed && vertices.count > 2
      let segmentCount = closed ? vertices.count : vertices.count - 1
      func direction(_ index: Int) -> SIMD2<Double> {
        simd_normalize(vertices[(index + 1) % vertices.count] - vertices[index])
      }
      var previous = direction(closed ? segmentCount - 1 : 0)
      for index in 0..<segmentCount {
        let from = vertices[index], to = vertices[(index + 1) % vertices.count]
        let current = direction(index)
        let normal = SIMD2(-current.y, current.x) * r
        let leftFrom = device(from + normal), rightTo = device(to - normal)
        output.append(leftFrom); output.append(device(to + normal)); output.append(rightTo)
        output.append(leftFrom); output.append(rightTo); output.append(device(from - normal))
        if index > 0 || closed {
          // The outer side of the turn; the inner side is under both quads.
          let cross = previous.x * current.y - previous.y * current.x, dot = simd_dot(previous, current)
          if cross != 0 || dot < 0 {
            let side = cross > 0 ? -r : r
            let outer = SIMD2(-previous.y, previous.x) * side
            if dot >= cosineStep {
              // A gentle turn: its chord is already within tolerance.
              output.append(device(from)); output.append(device(from + outer))
              output.append(device(from + SIMD2(-current.y, current.x) * side))
            } else {
              arc(from, from: outer, sweep: atan2(cross, dot))
            }
          }
        } else {
          fan(from, from: normal, count: capCount, turn: capTurn)
        }
        previous = current
      }
      if !closed {
        fan(vertices[vertices.count - 1], from: -SIMD2(-previous.y, previous.x) * r, count: capCount, turn: capTurn)
      }
    }
  }
}

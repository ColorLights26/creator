import Foundation

enum SceneRenderSignalEventBandV2: UInt8, CaseIterable {
  case none = 0
  case low = 1
  case body = 2
  case high = 3
  case broadband = 4
}

struct SceneRenderSignalEventV2: Equatable {
  let serial: Int64
  let active: Bool
  let timestampMicros: Int64
  let strength: Float
  let band: SceneRenderSignalEventBandV2
}

struct SceneRenderSignalFrameV2: Equatable {
  let sessionId: Int64
  let sequence: Int64
  let audioTimestampMicros: Int64
  let available: Bool
  let fresh: Bool
  let musicActive: Bool
  let tonalAvailable: Bool
  let dynamics: [Float]
  let channels: [Float]
  let spectrumSummary: [Float]
  let instantSpectrum: [Float]
  let smoothedSpectrum: [Float]
  let semantics: [Float]
  let rhythm: [Float]
  let onsets: [Float]
  let tonal: [Float]
  let impact: SceneRenderSignalEventV2
  let accent: SceneRenderSignalEventV2
  let beat: SceneRenderSignalEventV2
  let flash: SceneRenderSignalEventV2

  // SceneRenderSignalAuthorityV2 reserves the low session bit for music-map
  // authority. Event-driven programs must not confuse live beats with map cues.
  var usesMappedMusicAuthority: Bool { sessionId & 1 == 1 }
}

enum SceneRenderSignalFrameV2Codec {
  static let magic: UInt32 = 0x3256_5253
  static let version: UInt16 = 2
  static let byteLength = 520

  private static let floatBlockOffset = 40
  private static let eventBlockOffset = 424
  private static let eventStride = 24
  private static let knownFlags: UInt16 = 0x000F

  static func decode(_ data: Data) -> SceneRenderSignalFrameV2? {
    let bytes = [UInt8](data)
    guard bytes.count == byteLength,
          readUInt32(bytes, at: 0) == magic,
          readUInt16(bytes, at: 4) == version,
          readUInt32(bytes, at: 8) == UInt32(byteLength),
          readUInt32(bytes, at: 12) == 0
    else {
      return nil
    }

    let flags = readUInt16(bytes, at: 6)
    guard flags & ~knownFlags == 0 else {
      return nil
    }
    let sessionId = Int64(bitPattern: readUInt64(bytes, at: 16))
    let sequence = Int64(bitPattern: readUInt64(bytes, at: 24))
    let audioTimestampMicros = Int64(bitPattern: readUInt64(bytes, at: 32))
    guard sessionId >= 0, sequence >= 0, audioTimestampMicros >= 0 else {
      return nil
    }

    var floatOffset = floatBlockOffset
    func vector(_ count: Int) -> [Float]? {
      var values: [Float] = []
      values.reserveCapacity(count)
      for _ in 0..<count {
        let value = Float(bitPattern: readUInt32(bytes, at: floatOffset))
        floatOffset += MemoryLayout<Float>.size
        guard value.isFinite else {
          return nil
        }
        values.append(value)
      }
      return values
    }

    guard let dynamics = vector(6),
          let channels = vector(4),
          let spectrumSummary = vector(7),
          let instantSpectrum = vector(31),
          let smoothedSpectrum = vector(31),
          let semantics = vector(6),
          let rhythm = vector(4),
          let onsets = vector(4),
          let tonal = vector(3),
          floatOffset == eventBlockOffset
    else {
      return nil
    }

    var eventOffset = eventBlockOffset
    func event() -> SceneRenderSignalEventV2? {
      let serial = Int64(bitPattern: readUInt64(bytes, at: eventOffset))
      let timestamp = Int64(bitPattern: readUInt64(bytes, at: eventOffset + 8))
      let strength = Float(bitPattern: readUInt32(bytes, at: eventOffset + 16))
      let bandValue = bytes[eventOffset + 20]
      let activeValue = bytes[eventOffset + 21]
      let reserved = readUInt16(bytes, at: eventOffset + 22)
      eventOffset += eventStride
      guard serial >= 0,
            timestamp >= 0,
            strength.isFinite,
            let band = SceneRenderSignalEventBandV2(rawValue: bandValue),
            activeValue <= 1,
            reserved == 0
      else {
        return nil
      }
      return SceneRenderSignalEventV2(
        serial: serial,
        active: activeValue == 1,
        timestampMicros: timestamp,
        strength: strength,
        band: band
      )
    }

    guard let impact = event(),
          let accent = event(),
          let beat = event(),
          let flash = event()
    else {
      return nil
    }

    return SceneRenderSignalFrameV2(
      sessionId: sessionId,
      sequence: sequence,
      audioTimestampMicros: audioTimestampMicros,
      available: flags & 0x0001 != 0,
      fresh: flags & 0x0002 != 0,
      musicActive: flags & 0x0004 != 0,
      tonalAvailable: flags & 0x0008 != 0,
      dynamics: dynamics,
      channels: channels,
      spectrumSummary: spectrumSummary,
      instantSpectrum: instantSpectrum,
      smoothedSpectrum: smoothedSpectrum,
      semantics: semantics,
      rhythm: rhythm,
      onsets: onsets,
      tonal: tonal,
      impact: impact,
      accent: accent,
      beat: beat,
      flash: flash
    )
  }

  fileprivate static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) |
      UInt16(bytes[offset + 1]) << 8
  }

  fileprivate static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) |
      UInt32(bytes[offset + 1]) << 8 |
      UInt32(bytes[offset + 2]) << 16 |
      UInt32(bytes[offset + 3]) << 24
  }

  fileprivate static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
    UInt64(readUInt32(bytes, at: offset)) |
      UInt64(readUInt32(bytes, at: offset + 4)) << 32
  }
}

enum SceneRenderMusicCueTypeV1: UInt8 {
  case none = 0
  case beat = 1
  case accent = 2
  case impact = 3
  case transition = 4
  case drop = 5
  case release = 6
}

/// Resolved MusicMap structure that travels with one V2 frame
/// (`SceneRenderMusicStructureV1` in visual_contract). An untrusted block
/// carries zeros only, so family policies read it only when `mappedTrusted`.
struct SceneRenderMusicStructureV1: Equatable {
  let sessionId: Int64
  let sequence: Int64
  let mappedTrusted: Bool
  let energy: Float
  let tension: Float
  let anticipation: Float
  let beatPhase: Float
  let barPhase: Float
  let confidence: Float
  let motionScale: Float
  let cueSerial: Int64
  let cueType: SceneRenderMusicCueTypeV1
  let cueStrength: Float

  func pairs(with frame: SceneRenderSignalFrameV2) -> Bool {
    sessionId == frame.sessionId && sequence == frame.sequence
  }
}

enum SceneRenderMusicStructureV1Codec {
  static let magic: UInt32 = 0x314D_5253
  static let version: UInt16 = 1
  static let byteLength = 80

  private static let knownFlags: UInt16 = 0x0001

  static func decode(_ data: Data) -> SceneRenderMusicStructureV1? {
    let bytes = [UInt8](data)
    guard bytes.count == byteLength,
          SceneRenderSignalFrameV2Codec.readUInt32(bytes, at: 0) == magic,
          SceneRenderSignalFrameV2Codec.readUInt16(bytes, at: 4) == version,
          SceneRenderSignalFrameV2Codec.readUInt32(bytes, at: 8) == UInt32(byteLength),
          SceneRenderSignalFrameV2Codec.readUInt32(bytes, at: 12) == 0,
          bytes[73..<byteLength].allSatisfy({ $0 == 0 })
    else {
      return nil
    }
    let flags = SceneRenderSignalFrameV2Codec.readUInt16(bytes, at: 6)
    guard flags & ~knownFlags == 0,
          let cueType = SceneRenderMusicCueTypeV1(rawValue: bytes[72])
    else {
      return nil
    }
    let sessionId = Int64(bitPattern: SceneRenderSignalFrameV2Codec.readUInt64(bytes, at: 16))
    let sequence = Int64(bitPattern: SceneRenderSignalFrameV2Codec.readUInt64(bytes, at: 24))
    let cueSerial = Int64(bitPattern: SceneRenderSignalFrameV2Codec.readUInt64(bytes, at: 64))
    // energy, tension, anticipation, beatPhase, barPhase, confidence,
    // motionScale, cueStrength.
    let values = stride(from: 32, through: 60, by: 4).map {
      Float(bitPattern: SceneRenderSignalFrameV2Codec.readUInt32(bytes, at: $0))
    }
    let mappedTrusted = flags & 0x0001 != 0
    let cuePresent = cueType != .none
    guard sessionId >= 0, sequence >= 0, cueSerial >= 0,
          values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
          cuePresent == (cueSerial > 0),
          cuePresent || values[7] == 0,
          mappedTrusted || (!cuePresent && values.allSatisfy { $0 == 0 })
    else {
      return nil
    }
    return SceneRenderMusicStructureV1(
      sessionId: sessionId,
      sequence: sequence,
      mappedTrusted: mappedTrusted,
      energy: values[0],
      tension: values[1],
      anticipation: values[2],
      beatPhase: values[3],
      barPhase: values[4],
      confidence: values[5],
      motionScale: values[6],
      cueSerial: cueSerial,
      cueType: cueType,
      cueStrength: values[7]
    )
  }
}

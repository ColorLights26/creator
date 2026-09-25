import AVFoundation
import CoreImage
import CoreVideo
import CryptoKit
import Flutter
import Foundation
import ImageIO

@available(iOS 15.0, *)
typealias SceneSurfaceNativeProgram = SceneRenderV2ImageSurfaceRuntime.NativeProgram
import Metal
import UIKit

struct SceneRenderV2RGBGainConfig: Equatable {
  let flowGain: Double
  let sparkGain: Double
  let maxGain: Double
  let flowAttackSeconds: Double
  let flowReleaseSeconds: Double
  let sparkAttackSeconds: Double
  let sparkReleaseSeconds: Double
  let framesPerSecond: Int

  static func decode(_ value: Any?) -> Self? {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys) == Set(["audioReactive", "effect"]),
      parameters["audioReactive"] as? Bool == true,
      let effect = parameters["effect"] as? [String: Any],
      Set(effect.keys) == Set([
        "kind", "flowGain", "sparkGain", "maxGain", "flowAttackMs",
        "flowReleaseMs", "sparkAttackMs", "sparkReleaseMs",
        "framesPerSecond",
      ]),
      effect["kind"] as? String == "rgb_gain_v1"
    else { return nil }
    func bounded(_ key: String, _ minimum: Double, _ maximum: Double) -> Double? {
      guard
        let value = (effect[key] as? NSNumber)?.doubleValue,
        value.isFinite,
        value >= minimum,
        value <= maximum
      else { return nil }
      return value
    }
    func milliseconds(_ key: String) -> Double? {
      guard
        let value = (effect[key] as? NSNumber)?.intValue,
        value >= 16,
        value <= 5_000
      else { return nil }
      return Double(value) / 1_000
    }
    guard
      let flowGain = bounded("flowGain", 0, 0.10),
      let sparkGain = bounded("sparkGain", 0, 0.10),
      let maxGain = bounded("maxGain", 0, 0.10),
      let flowAttack = milliseconds("flowAttackMs"),
      let flowRelease = milliseconds("flowReleaseMs"),
      let sparkAttack = milliseconds("sparkAttackMs"),
      let sparkRelease = milliseconds("sparkReleaseMs"),
      let framesPerSecond = (effect["framesPerSecond"] as? NSNumber)?.intValue,
      framesPerSecond >= 1,
      framesPerSecond <= 60,
      maxGain > 0,
      flowGain > 0 || sparkGain > 0
    else { return nil }
    return Self(
      flowGain: flowGain,
      sparkGain: sparkGain,
      maxGain: maxGain,
      flowAttackSeconds: flowAttack,
      flowReleaseSeconds: flowRelease,
      sparkAttackSeconds: sparkAttack,
      sparkReleaseSeconds: sparkRelease,
      framesPerSecond: framesPerSecond
    )
  }
}

final class SceneRenderV2RGBGainState {
  let config: SceneRenderV2RGBGainConfig
  private var flowEnvelope = 0.0
  private var sparkEnvelope = 0.0
  private var lastAudioTimestampMicros: Int64 = -1
  private(set) var gain = 1.0

  init(config: SceneRenderV2RGBGainConfig) { self.config = config }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    let reactive = frame.available && frame.fresh && frame.musicActive
    let delta = lastAudioTimestampMicros < 0
      ? 1.0 / Double(config.framesPerSecond)
      : min(
        0.25,
        max(
          0,
          Double(frame.audioTimestampMicros - lastAudioTimestampMicros) /
            1_000_000
        )
      )
    lastAudioTimestampMicros = frame.audioTimestampMicros
    let flowTarget = reactive ? unit(Double(frame.channels[3])) : 0
    let sparkTarget = reactive ? unit(Double(frame.channels[2])) : 0
    flowEnvelope = smooth(
      flowEnvelope,
      flowTarget,
      delta,
      config.flowAttackSeconds,
      config.flowReleaseSeconds
    )
    sparkEnvelope = smooth(
      sparkEnvelope,
      sparkTarget,
      delta,
      config.sparkAttackSeconds,
      config.sparkReleaseSeconds
    )
    if flowTarget == 0, flowEnvelope < 0.0001 { flowEnvelope = 0 }
    if sparkTarget == 0, sparkEnvelope < 0.0001 { sparkEnvelope = 0 }
    let next = 1 + min(
      config.maxGain,
      flowEnvelope * config.flowGain + sparkEnvelope * config.sparkGain
    )
    let changed = next != gain
    gain = next
    return changed
  }

  func apply(to input: CIImage) -> CIImage {
    guard gain > 1.00001 else { return input }
    return input.applyingFilter(
      "CIColorMatrix",
      parameters: [
        "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ]
    )
  }

  private func smooth(
    _ current: Double,
    _ target: Double,
    _ delta: Double,
    _ attack: Double,
    _ release: Double
  ) -> Double {
    guard delta > 0, current != target else { return current }
    let seconds = max(target > current ? attack : release, 0.001)
    return current + (target - current) * (1 - Foundation.exp(-delta / seconds))
  }

  private func unit(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(1, max(0, value))
  }
}

struct SceneRenderV2NaturalReactiveLightConfig: Equatable {
  let flowGain: Double
  let sparkGain: Double
  let flowAttackSeconds: Double
  let flowReleaseSeconds: Double
  let sparkAttackSeconds: Double
  let sparkReleaseSeconds: Double
  let auroraTop: Double
  let auroraBottom: Double
  let waveTop: Double
  let waveBottom: Double
  let auroraGreenThreshold: Double
  let waveCyanThreshold: Double
  let waveBlueMinimum: Double
  let celestialProfile: Bool
  let celestialTop: Double
  let celestialBottom: Double
  let nebulaLumaThreshold: Double
  let nebulaChromaThreshold: Double
  let starLumaThreshold: Double

  static func decode(_ value: Any?) -> Self? {
    guard let parameters = value as? [String: Any],
          Set(parameters.keys) == Set(["audioReactive", "effect"]),
          parameters["audioReactive"] as? Bool == true,
          let effect = parameters["effect"] as? [String: Any],
          Set(effect.keys) == Set([
            "kind", "profile", "flowGain", "sparkGain", "flowAttackMs",
            "flowReleaseMs", "sparkAttackMs", "sparkReleaseMs", "auroraTop",
            "auroraBottom", "waveTop", "waveBottom", "auroraGreenThreshold",
            "waveCyanThreshold", "waveBlueMinimum", "celestialTop",
            "celestialBottom", "nebulaLumaThreshold", "nebulaChromaThreshold",
            "starLumaThreshold",
          ]),
          effect["kind"] as? String == "natural_reactive_light_v1",
          let profile = effect["profile"] as? String,
          ["coastal", "celestial"].contains(profile)
    else { return nil }
    func bounded(_ key: String, _ minimum: Double, _ maximum: Double) -> Double? {
      guard let value = (effect[key] as? NSNumber)?.doubleValue,
            value.isFinite else { return nil }
      return min(max(value, minimum), maximum)
    }
    func milliseconds(_ key: String) -> Double? {
      guard let value = (effect[key] as? NSNumber)?.intValue else { return nil }
      return Double(min(max(value, 16), 5_000)) / 1_000
    }
    guard let flowGain = bounded("flowGain", 0, 0.24),
          let sparkGain = bounded("sparkGain", 0, 0.65),
          let auroraTop = bounded("auroraTop", 0, 0.9),
          let auroraBottom = bounded("auroraBottom", 0.1, 1),
          let waveTop = bounded("waveTop", 0, 0.95),
          let waveBottom = bounded("waveBottom", 0.1, 1),
          let celestialTop = bounded("celestialTop", 0, 0.9),
          let celestialBottom = bounded("celestialBottom", 0.1, 1),
          let flowAttack = milliseconds("flowAttackMs"),
          let flowRelease = milliseconds("flowReleaseMs"),
          let sparkAttack = milliseconds("sparkAttackMs"),
          let sparkRelease = milliseconds("sparkReleaseMs"),
          let auroraThreshold = bounded("auroraGreenThreshold", 0, 0.5),
          let waveThreshold = bounded("waveCyanThreshold", 0, 0.6),
          let blueMinimum = bounded("waveBlueMinimum", 0, 0.8),
          let nebulaLuma = bounded("nebulaLumaThreshold", 0.02, 0.8),
          let nebulaChroma = bounded("nebulaChromaThreshold", 0, 0.8),
          let starLuma = bounded("starLumaThreshold", 0.2, 0.98),
          flowGain > 0 || sparkGain > 0,
          auroraTop < auroraBottom,
          waveTop < waveBottom,
          celestialTop < celestialBottom
    else { return nil }
    return Self(
      flowGain: flowGain,
      sparkGain: sparkGain,
      flowAttackSeconds: flowAttack,
      flowReleaseSeconds: flowRelease,
      sparkAttackSeconds: sparkAttack,
      sparkReleaseSeconds: sparkRelease,
      auroraTop: auroraTop,
      auroraBottom: auroraBottom,
      waveTop: waveTop,
      waveBottom: waveBottom,
      auroraGreenThreshold: auroraThreshold,
      waveCyanThreshold: waveThreshold,
      waveBlueMinimum: blueMinimum,
      celestialProfile: profile == "celestial",
      celestialTop: celestialTop,
      celestialBottom: celestialBottom,
      nebulaLumaThreshold: nebulaLuma,
      nebulaChromaThreshold: nebulaChroma,
      starLumaThreshold: starLuma
    )
  }
}

final class SceneRenderV2NaturalReactiveLightState {
  let config: SceneRenderV2NaturalReactiveLightConfig
  private var flowEnvelope = 0.0
  private var sparkEnvelope = 0.0
  private var lastAudioTimestampMicros: Int64 = -1
  private(set) var flow = 0.0
  private(set) var spark = 0.0

  private static let kernel = CIColorKernel(source: """
    kernel vec4 sceneNaturalReactiveLightV1(
      __sample source, vec2 origin, vec2 size, float flow, float spark,
      float auroraTop, float auroraBottom, float waveTop, float waveBottom,
      float auroraGreenThreshold, float waveCyanThreshold, float waveBlueMinimum,
      float profile, float celestialTop, float celestialBottom,
      float nebulaLumaThreshold, float nebulaChromaThreshold, float starLumaThreshold
    ) {
      vec2 uv=(destCoord()-origin)/size; uv.y=1.0-uv.y;
      vec4 color=unpremultiply(source);
      float auroraZone=smoothstep(auroraTop,auroraTop+0.065,uv.y)*
        (1.0-smoothstep(auroraBottom-0.065,auroraBottom,uv.y));
      float waveZone=smoothstep(waveTop,waveTop+0.055,uv.y)*
        (1.0-smoothstep(waveBottom-0.055,waveBottom,uv.y));
      float aurora=smoothstep(auroraGreenThreshold,auroraGreenThreshold+0.185,
        color.g-color.r);
      aurora*=smoothstep(-0.08,0.15,color.g-color.b);
      aurora*=smoothstep(0.16,0.68,color.g)*auroraZone;
      float wave=smoothstep(waveCyanThreshold,waveCyanThreshold+0.24,
        color.b-color.r);
      wave*=smoothstep(0.025,0.18,color.g-color.r);
      wave*=smoothstep(waveBlueMinimum,min(waveBlueMinimum+0.50,1.0),color.b)*
        waveZone;
      float celestialZone=smoothstep(celestialTop,celestialTop+0.065,uv.y)*
        (1.0-smoothstep(celestialBottom-0.065,celestialBottom,uv.y));
      float luma=dot(color.rgb,vec3(0.2126,0.7152,0.0722));
      float peak=max(max(color.r,color.g),color.b);
      float trough=min(min(color.r,color.g),color.b);
      float nebula=smoothstep(nebulaLumaThreshold,
        min(nebulaLumaThreshold+0.34,1.0),luma);
      nebula*=smoothstep(nebulaChromaThreshold,
        min(nebulaChromaThreshold+0.24,1.0),peak-trough)*celestialZone;
      float warmCore=smoothstep(0.02,0.14,color.r-max(color.g,color.b));
      nebula*=(1.0-warmCore)*(1.0-smoothstep(0.62,0.82,luma));
      float star=smoothstep(starLumaThreshold,min(starLumaThreshold+0.20,1.0),peak);
      star*=smoothstep(starLumaThreshold*0.72,starLumaThreshold,luma);
      star*=(1.0-smoothstep(0.12,0.35,peak-trough))*
        (1.0-smoothstep(0.82,0.96,luma))*celestialZone;
      if(profile>0.5){
        float field=smoothstep(0.06,0.24,luma)*
          (1.0-smoothstep(0.48,0.72,luma))*celestialZone;
        color.rgb+=aurora*(flow*1.10+spark*0.70)*vec3(0.060,0.850,0.300);
        color.rgb+=nebula*(flow*0.50+spark*0.65)*vec3(0.180,0.110,0.260);
        color.rgb*=1.0+field*spark*0.42;
        color.rgb*=1.0+nebula*spark*0.18;
        color.rgb*=1.0+star*(spark*1.25+flow*0.15);
        color.rgb+=star*spark*vec3(0.080,0.120,0.180);
      }else{
        float waveGain=wave*(flow*0.75+spark*1.60);
        color.rgb*=1.0+waveGain;
        color.rgb+=wave*spark*vec3(0.040,0.160,0.250);
        color.rgb+=aurora*flow*vec3(0.120,0.950,0.400);
      }
      color.rgb=clamp(color.rgb,0.0,1.0);
      return premultiply(color);
    }
  """)

  init(config: SceneRenderV2NaturalReactiveLightConfig) { self.config = config }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    let reactive = frame.available && frame.fresh && frame.musicActive
    let delta = lastAudioTimestampMicros < 0
      ? 1.0 / 30.0
      : min(0.25, max(0, Double(frame.audioTimestampMicros - lastAudioTimestampMicros) / 1_000_000))
    lastAudioTimestampMicros = frame.audioTimestampMicros
    let flowTarget = reactive ? shaped(Double(frame.channels[3]), flowSignal: true) : 0
    let sparkTarget = reactive ? shaped(Double(frame.channels[2]), flowSignal: false) : 0
    flowEnvelope = smooth(
      flowEnvelope, flowTarget, delta, config.flowAttackSeconds, config.flowReleaseSeconds
    )
    sparkEnvelope = smooth(
      sparkEnvelope, sparkTarget, delta, config.sparkAttackSeconds, config.sparkReleaseSeconds
    )
    if flowTarget == 0, flowEnvelope < 0.0001 { flowEnvelope = 0 }
    if sparkTarget == 0, sparkEnvelope < 0.0001 { sparkEnvelope = 0 }
    let nextFlow = (config.celestialProfile ? flowEnvelope * flowEnvelope : flowEnvelope) *
      config.flowGain
    let nextSpark = (config.celestialProfile ? sparkEnvelope * sparkEnvelope : sparkEnvelope) *
      config.sparkGain
    let changed = nextFlow != flow || nextSpark != spark
    flow = nextFlow
    spark = nextSpark
    return changed
  }

  func apply(to input: CIImage) -> CIImage {
    guard flow > 0.00001 || spark > 0.00001,
          let kernel = Self.kernel else { return input }
    let extent = input.extent
    return kernel.apply(
      extent: extent,
      arguments: [
        input, CIVector(x: extent.minX, y: extent.minY),
        CIVector(x: extent.width, y: extent.height), flow, spark,
        config.auroraTop, config.auroraBottom, config.waveTop, config.waveBottom,
        config.auroraGreenThreshold, config.waveCyanThreshold,
        config.waveBlueMinimum, config.celestialProfile ? 1.0 : 0.0,
        config.celestialTop, config.celestialBottom, config.nebulaLumaThreshold,
        config.nebulaChromaThreshold, config.starLumaThreshold,
      ]
    )?.cropped(to: extent) ?? input
  }

  private func shaped(_ value: Double, flowSignal: Bool) -> Double {
    let unit = min(1, max(0, value))
    guard config.celestialProfile else { return unit }
    let lower = flowSignal ? 0.30 : 0.10
    let upper = flowSignal ? 0.50 : 0.70
    let normalized = min(1, max(0, (unit - lower) / (upper - lower)))
    return normalized * normalized * (3 - 2 * normalized)
  }

  private func smooth(
    _ current: Double,
    _ target: Double,
    _ delta: Double,
    _ attack: Double,
    _ release: Double
  ) -> Double {
    guard delta > 0, current != target else { return current }
    let seconds = max(target > current ? attack : release, 0.001)
    return current + (target - current) * (1 - Foundation.exp(-delta / seconds))
  }
}

struct SceneRenderV2RadialWarpLayer {
  let id: String
  let opacity: CGFloat
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let particleCountsByQuality: [String: Int]
  let bloomByQuality: [String: Bool]
}

final class SceneRenderV2RadialWarpState {
  let layerID: String
  private(set) var elapsedSeconds = 0.0
  private(set) var flowResponse = 0.0
  private(set) var bassResponse = 0.0
  private(set) var sparkResponse = 0.0
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?
  private var flowTarget = 0.0
  private var bassTarget = 0.0
  private var sparkTarget = 0.0

  init(layerID: String) {
    self.layerID = layerID
  }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    let reactive = frame.available && frame.fresh && frame.musicActive
    let nextFlow = reactive ? unit(frame.channels[3]) : 0
    let nextBass = reactive ? unit(frame.channels[0]) : 0
    let nextSpark = reactive ? unit(frame.channels[2]) : 0
    let changed = nextFlow != flowTarget || nextBass != bassTarget ||
      nextSpark != sparkTarget
    flowTarget = nextFlow
    bassTarget = nextBass
    sparkTarget = nextSpark
    return changed
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    for _ in 0..<due { step() }
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
  }

  private func step() {
    flowResponse = follow(flowResponse, flowTarget, 0.12, 0.52)
    bassResponse = follow(bassResponse, bassTarget, 0.055, 0.34)
    sparkResponse = follow(sparkResponse, sparkTarget, 0.025, 0.20)
    elapsedSeconds += Self.sourceInterval
  }

  private func follow(
    _ current: Double,
    _ target: Double,
    _ attack: Double,
    _ release: Double
  ) -> Double {
    let seconds = target > current ? attack : release
    let amount = 1 - Foundation.exp(-Self.sourceInterval / seconds)
    return current + (target - current) * amount
  }

  private func unit(_ value: Float) -> Double {
    min(1, max(0, Double(value)))
  }

  static let sourceInterval = 1.0 / 30.0
  private static let maximumHiddenSteps = 120
}

struct SceneRenderV2SnowfallLayer {
  let id: String
  let opacity: CGFloat
  let particleData: Data
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let particleCountsByQuality: [String: Int]
}

final class SceneRenderV2SnowfallState {
  let layerID: String
  private(set) var elapsedSeconds = 0.0
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?

  init(layerID: String) {
    self.layerID = layerID
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    elapsedSeconds += Double(due) * Self.sourceInterval
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
  }

  static let sourceInterval = 1.0 / 30.0
  private static let maximumHiddenSteps = 120
}

struct SceneRenderV2PaintedStarlightLayer {
  let id: String
  let opacity: CGFloat
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let intensityScaleByQuality: [String: Double]
}

final class SceneRenderV2PaintedStarlightState {
  let layerID: String
  private(set) var elapsedSeconds = 0.0
  private(set) var flowResponse = 0.0
  private(set) var sparkResponse = 0.0
  private(set) var moonBand = 2
  private(set) var starBands = Array(repeating: 2, count: 5)
  private var flowTarget = 0.0
  private var sparkTarget = 0.0
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?

  init(layerID: String) { self.layerID = layerID }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    let reactive = frame.available && frame.fresh && frame.musicActive
    let nextFlow = reactive ? unit(frame.channels[3]) : 0
    let nextSpark = reactive ? unit(frame.channels[2]) : 0
    let changed = nextFlow != flowTarget || nextSpark != sparkTarget
    flowTarget = nextFlow
    sparkTarget = nextSpark
    return changed
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    for _ in 0..<due { step() }
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
  }

  private func step() {
    flowResponse = follow(flowResponse, flowTarget, 0.38, 1.35)
    sparkResponse = follow(sparkResponse, sparkTarget, 0.06, 0.42)
    elapsedSeconds += Self.sourceInterval
    let breath = 0.5 + 0.5 * Foundation.sin(elapsedSeconds * .pi * 2 / 7.2)
    moonBand = band(0.07 + breath * 0.05 + flowResponse * 0.72 + sparkResponse * 0.34)
    for index in starBands.indices {
      let phase = Double(index) * 1.31
      let shimmer = 0.5 + 0.5 * Foundation.sin(
        elapsedSeconds * (0.78 + Double(index) * 0.035) + phase
      )
      let responseWeight = 0.76 + Double(index % 3) * 0.10
      starBands[index] = band(
        0.06 + shimmer * 0.04 + flowResponse * 0.10 +
          sparkResponse * responseWeight * 0.92
      )
    }
  }

  private func follow(
    _ current: Double,
    _ target: Double,
    _ attack: Double,
    _ release: Double
  ) -> Double {
    let seconds = target > current ? attack : release
    return current + (target - current) * (1 - Foundation.exp(-Self.sourceInterval / seconds))
  }

  private func band(_ value: Double) -> Int {
    min(15, max(0, Int((min(1, max(0, value)) * 15).rounded())))
  }

  private func unit(_ value: Float) -> Double { min(1, max(0, Double(value))) }

  static let sourceInterval = 1.0 / 30.0
  private static let maximumHiddenSteps = 120
}

struct SceneRenderV2NeonPulseControls: Equatable {
  var particleSize = 1.0
  var animationSeconds = 10.0

  static func parse(_ parameters: [String: Any]) -> Self? {
    let mode = parameters["mode"] as? String
    guard parameters["mode"] == nil || mode == "" || mode == "default" || mode == "smooth",
      let values = parameters["options"] as? [String: Any] ??
        (parameters["options"] == nil ? [:] : nil),
      Set(values.keys).isSubset(of: ["Smooth", "Particle Size", "Animation Speed"]),
      values["Smooth"] == nil || values["Smooth"] is Bool,
      let size = SceneRenderV2MagicStarsControls.scalar(values, "Particle Size", 1, 0.5...3),
      let speed = SceneRenderV2MagicStarsControls.scalar(values, "Animation Speed", 10, 5...20)
    else { return nil }
    // Smooth is an authored no-op in NeonPulse; do not invent new animation.
    return Self(particleSize: size, animationSeconds: speed)
  }
}

struct SceneRenderV2MagicStarsControls: Equatable {
  var starSize = 1.0
  var dynamicCount = 170
  var staticCount = 10
  var bias = 0.5
  var flashingFraction = 0.5
  var shootingProbability = 0.05
  var colorIndex = 0

  static func scalar(_ values: [String: Any], _ key: String, _ fallback: Double,
                     _ range: ClosedRange<Double>) -> Double? {
    guard let raw = values[key] else { return fallback }
    guard let number = raw as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
      range.contains(number.doubleValue) else { return nil }
    return number.doubleValue
  }

  static func parse(_ parameters: [String: Any]) -> Self? {
    guard parameters["mode"] == nil || parameters["mode"] as? String == "" ||
        parameters["mode"] as? String == "default",
      let values = parameters["options"] as? [String: Any] ??
        (parameters["options"] == nil ? [:] : nil),
      Set(values.keys).isSubset(of: ["Star Size", "Num Dynamic Stars", "Num Static Stars",
        "Star Distribution Bias", "Shooting Star Probability", "Flashing Percentage", "Star Color"]),
      let size = scalar(values, "Star Size", 1, 0.5...2),
      let dynamic = scalar(values, "Num Dynamic Stars", 170, 50...300),
      let fixed = scalar(values, "Num Static Stars", 10, 5...50),
      let bias = scalar(values, "Star Distribution Bias", 0.5, 0.1...1),
      let probability = scalar(values, "Shooting Star Probability", 0.05, 0.01...0.5),
      let flashing = scalar(values, "Flashing Percentage", 0.5, 0...1),
      let color = scalar(values, "Star Color", 0, 0...3), color == floor(color)
    else { return nil }
    return Self(starSize: size, dynamicCount: Int(dynamic), staticCount: Int(fixed),
      bias: bias, flashingFraction: flashing, shootingProbability: probability,
      colorIndex: Int(color))
  }

  var color: SIMD3<Float> {
    let colors: [UInt32] = [0xffffff, 0x448aff, 0xff5252, 0x69f0ae]
    let value = colors[colorIndex]
    return SIMD3(Float((value >> 16) & 255) / 255,
      Float((value >> 8) & 255) / 255, Float(value & 255) / 255)
  }
}

struct SceneRenderV2MagicStarsLayer {
  let id: String
  let opacity: CGFloat
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let intensityScaleByQuality: [String: Double]
  var controls = SceneRenderV2MagicStarsControls()
}

/// Session-seeded replay of the current Magic Stars field. The authored state
/// advances at 60 Hz even when a lower quality presents fewer frames.
final class SceneRenderV2MagicStarsState {
  let layerID: String
  let randomSeed: UInt32
  private(set) var attributes: [Float] = []
  private(set) var attributesRevision = 0
  private(set) var attributesIdentity = UUID()
  private(set) var controls = SceneRenderV2MagicStarsControls()
  private(set) var elapsedSeconds = 0.0
  private(set) var noiseLevel = 0.5
  private(set) var authoredFrame: Int64 = 0
  private(set) var shootingActive = false
  private(set) var shootingStartX = 0.0
  private(set) var shootingEndX = 0.0
  private(set) var shootingProgress = 0.0
  private var random: LCG32
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?
  private var shootingFrames = 0
  private var retryFrames = 0

  init(layerID: String, sessionSeed: UInt32) {
    self.layerID = layerID
    randomSeed = Self.nodeSeed(sessionSeed: sessionSeed, nodeID: layerID)
    random = LCG32(seed: randomSeed)
    regenerate(dynamic: true, fixed: true)
    attemptShootingStar()
  }

  func applyControls(_ next: SceneRenderV2MagicStarsControls) {
    let dynamic = next.dynamicCount != controls.dynamicCount || next.bias != controls.bias ||
      next.flashingFraction != controls.flashingFraction
    let fixed = next.staticCount != controls.staticCount || next.bias != controls.bias
    controls = next
    if dynamic || fixed { regenerate(dynamic: dynamic, fixed: fixed) }
  }

  func copyingControls(_ next: SceneRenderV2MagicStarsControls) -> SceneRenderV2MagicStarsState {
    // Preserve the exact field/random cursor when changing only size or color.
    return clone(with: next)
  }

  private init(copying previous: SceneRenderV2MagicStarsState) {
    layerID = previous.layerID; randomSeed = previous.randomSeed
    random = previous.random
    attributes = previous.attributes; attributesRevision = previous.attributesRevision
    attributesIdentity = previous.attributesIdentity
    dynamicAttributes = previous.dynamicAttributes; staticAttributes = previous.staticAttributes
    controls = previous.controls
    elapsedSeconds = previous.elapsedSeconds; noiseLevel = previous.noiseLevel
    authoredFrame = previous.authoredFrame; shootingActive = previous.shootingActive
    shootingStartX = previous.shootingStartX; shootingEndX = previous.shootingEndX
    shootingProgress = previous.shootingProgress; shootingFrames = previous.shootingFrames
    retryFrames = previous.retryFrames; playing = previous.playing
    nextStepHostTime = previous.nextStepHostTime
  }

  private func clone(with next: SceneRenderV2MagicStarsControls) -> SceneRenderV2MagicStarsState {
    let copy = SceneRenderV2MagicStarsState(copying: self)
    copy.applyControls(next)
    return copy
  }

  private var dynamicAttributes = [Float]()
  private var staticAttributes = [Float]()
  private func regenerate(dynamic: Bool, fixed: Bool) {
    if dynamic {
      var values = [Float]()
      values.reserveCapacity(controls.dynamicCount * Self.attributeFloats)
      for index in 0..<controls.dynamicCount {
      let flashing = random.nextDouble() < controls.flashingFraction
      let x = random.nextDouble()
      let y = 1 - Foundation.pow(random.nextDouble(), controls.bias)
      let radius = random.nextDouble()
      let blinking = random.nextBool()
      let opacity = 0.5 + random.nextDouble() * 0.5
      let phase = random.nextDouble() * 2 * Double.pi
      values.append(contentsOf: [
        Float(x), Float(y), Float(radius), Float(opacity), Float(phase),
        flashing ? 1 : 0, blinking ? 1 : 0, 1, Float(index),
      ])
      }
      dynamicAttributes = values
    }
    if fixed {
      var values = [Float]()
      values.reserveCapacity(controls.staticCount * Self.attributeFloats)
      for index in 0..<controls.staticCount {
      let x = random.nextDouble()
      let y = 1 - Foundation.pow(random.nextDouble(), controls.bias)
      let radius = random.nextDouble()
      let opacity = 0.5 + random.nextDouble() * 0.5
      let phase = random.nextDouble() * 2 * Double.pi
      values.append(contentsOf: [
        Float(x), Float(y), Float(radius), Float(opacity), Float(phase),
        0, 0, 0, Float(index),
      ])
      }
      staticAttributes = values
    }
    attributes = dynamicAttributes + staticAttributes
    attributesRevision += 1
    attributesIdentity = UUID()
  }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    let reactive = frame.available && frame.fresh && frame.musicActive
    let next = reactive ? min(1, max(0, Double(frame.dynamics[3]))) : 0
    guard next != noiseLevel else { return false }
    noiseLevel = next
    return true
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    for _ in 0..<due { step() }
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
    if next && !shootingActive { attemptShootingStar() }
  }

  private func step() {
    authoredFrame += 1
    elapsedSeconds += Self.sourceInterval
    if shootingActive {
      shootingFrames += 1
      shootingProgress = min(1, Double(shootingFrames) / 180)
      if shootingFrames >= 180 {
        shootingActive = false
        shootingProgress = 1
        attemptShootingStar()
      }
      return
    }
    retryFrames += 1
    if retryFrames >= 60 { attemptShootingStar() }
  }

  private func attemptShootingStar() {
    retryFrames = 0
    guard random.nextDouble() <= controls.shootingProbability else { return }
    shootingStartX = random.nextDouble()
    shootingEndX = shootingStartX + (random.nextDouble() - 0.5) * 0.5
    shootingFrames = 0
    shootingProgress = 0
    shootingActive = true
  }

  private struct LCG32 {
    private var state: UInt32
    init(seed: UInt32) { state = seed }
    mutating func nextUInt32() -> UInt32 {
      state = 1_664_525 &* state &+ 1_013_904_223
      return state
    }
    mutating func nextDouble() -> Double {
      Double(nextUInt32()) / 4_294_967_296.0
    }
    mutating func nextBool() -> Bool { nextUInt32() & 1 != 0 }
  }

  static func nodeSeed(sessionSeed: UInt32, nodeID: String) -> UInt32 {
    var hash = UInt32(0x811c9dc5) ^ sessionSeed
    for byte in nodeID.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* UInt32(0x01000193)
    }
    return hash
  }

  static let dynamicCount = 170
  static let staticCount = 10
  static let totalCount = dynamicCount + staticCount
  static let attributeFloats = 9
  static let sourceInterval = 1.0 / 60.0
  private static let maximumHiddenSteps = 240
}

struct SceneRenderV2BlueSkyLayer {
  let id: String
  let opacity: CGFloat
  let renderScales: [String: Double]
}

struct SceneRenderV2MagicMoonLayer {
  let id: String
  let opacity: CGFloat
  let texture: CIImage
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
}

/// Replays the observed one-frame-per-second celestial arc. Quality changes
/// reuse this state, so changing render scale never restarts the moon.
final class SceneRenderV2MagicMoonState {
  let layerID: String
  private(set) var progress: Double
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?

  init(layerID: String, now: Date = Date()) {
    self.layerID = layerID
    let micros = Int64((now.timeIntervalSince1970 * 1_000_000).rounded(.down))
    progress = Double(micros % Self.cycleMicros) / Double(Self.cycleMicros)
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    progress = (progress + Double(due) / Double(Self.cycleSeconds))
      .truncatingRemainder(dividingBy: 1)
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
  }

  static let cycleMicros: Int64 = 5_400_000_000
  static let cycleSeconds = 5_400
  static let sourceInterval = 1.0
  private static let maximumHiddenSteps = 60
}

struct SceneRenderV2RadiantEmissionLayer {
  let id: String
  let opacity: CGFloat
  let centerX: Double
  let centerY: Double
  let intensity: Double
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let intensityScaleByQuality: [String: Double]
}

struct SceneRenderV2RainbowWaterfallLayer {
  let id: String
  let opacity: CGFloat
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
}

/// Authored 30 Hz Rainbow Waterfall timeline driven by the resolved V2 authority.
/// The same state survives every continuous quality transition.
final class SceneRenderV2RainbowWaterfallState {
  let layerID: String
  private(set) var phase = 0.0
  private(set) var cyclesPerSecond = baseCyclesPerSecond
  private(set) var bass = 0.0
  private(set) var body = 0.0
  private(set) var pulse = 0.0
  private(set) var energy = 0.0
  private(set) var flow = 0.0
  private var bassTarget = 0.0
  private var bodyTarget = 0.0
  private var energyTarget = 0.0
  private var flowTarget = 0.0
  private var mappedBeatTarget = 0.0
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?
  private var signalSessionID: Int64 = -1
  private var lastBeatSerial: Int64 = 0
  private var lastImpactSerial: Int64 = 0

  init(layerID: String) { self.layerID = layerID }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    if frame.sessionId != signalSessionID {
      signalSessionID = frame.sessionId
      lastBeatSerial = 0
      lastImpactSerial = 0
    }
    let reactive = frame.available && frame.fresh && frame.musicActive
    let nextBass = reactive ? unit(frame.channels[0]) : 0
    let nextBody = reactive ? unit(frame.channels[1]) : 0
    let nextEnergy = reactive
      ? max(unit(frame.dynamics[3]), unit(frame.dynamics[2]) * 0.76)
      : 0
    let nextFlow = reactive ? unit(frame.channels[3]) : 0
    let nextMappedBeat = reactive && frame.usesMappedMusicAuthority
      ? pow(max(0, 1 - unit(frame.rhythm[1]) * 4), 2.2) : 0
    var eventStrength = 0.0
    if reactive {
      if frame.beat.active, frame.beat.serial > lastBeatSerial {
        lastBeatSerial = frame.beat.serial
        eventStrength = max(eventStrength, unit(frame.beat.strength))
      }
      if frame.impact.active, frame.impact.serial > lastImpactSerial {
        lastImpactSerial = frame.impact.serial
        eventStrength = max(eventStrength, unit(frame.impact.strength))
      }
    }
    let previousPulse = pulse
    pulse = min(1, max(pulse, eventStrength, nextMappedBeat * 0.28))
    let changed = nextBass != bassTarget || nextBody != bodyTarget ||
      nextEnergy != energyTarget || nextFlow != flowTarget ||
      nextMappedBeat != mappedBeatTarget || pulse != previousPulse
    bassTarget = nextBass
    bodyTarget = nextBody
    energyTarget = nextEnergy
    flowTarget = nextFlow
    mappedBeatTarget = nextMappedBeat
    return changed
  }

  func advance(hostTime: CFTimeInterval, motionRateScale: Double = 1) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    for _ in 0..<due { step(motionRateScale: motionRateScale) }
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
  }

  private func step(motionRateScale: Double = 1) {
    let delta = Self.sourceInterval
    pulse *= Foundation.exp(-delta / 0.22)
    pulse = min(1, max(pulse, mappedBeatTarget * 0.28))
    bass = follow(bass, target: bassTarget, delta: delta, attack: 0.06, release: 0.38)
    body = follow(body, target: bodyTarget, delta: delta, attack: 0.12, release: 0.70)
    energy = follow(
      energy, target: energyTarget, delta: delta, attack: 0.18, release: 0.85
    )
    flow = follow(flow, target: flowTarget, delta: delta, attack: 0.22, release: 1.0)
    let continuousDrive = max(energy, bass * 0.92, body * 0.80, flow * 0.72)
    let rhythmicDrive = max(pulse, mappedBeatTarget)
    let speedDrive = min(1, max(0, continuousDrive * 0.45 + rhythmicDrive * 0.85))
    let normalized = min(1, max(0, (speedDrive - 0.03) / 0.97))
    let boundedMotionRateScale = min(1, max(0.25, motionRateScale))
    let targetCycles = (Self.baseCyclesPerSecond +
      (Self.maximumCyclesPerSecond - Self.baseCyclesPerSecond) * pow(normalized, 1.55)) *
      boundedMotionRateScale
    let speedConstant = targetCycles > cyclesPerSecond ? 0.09 : 0.48
    cyclesPerSecond += (targetCycles - cyclesPerSecond) *
      (1 - Foundation.exp(-delta / speedConstant))
    cyclesPerSecond = min(
      Self.maximumCyclesPerSecond * boundedMotionRateScale,
      max(Self.baseCyclesPerSecond * boundedMotionRateScale, cyclesPerSecond)
    )
    let wrapped = (phase + delta * cyclesPerSecond).truncatingRemainder(dividingBy: 1)
    phase = wrapped < 1e-12 || 1 - wrapped < 1e-12 ? 0 : wrapped
  }

  private func follow(
    _ current: Double,
    target: Double,
    delta: Double,
    attack: Double,
    release: Double
  ) -> Double {
    let amount = 1 - Foundation.exp(-delta / (target > current ? attack : release))
    return min(1, max(0, current + (target - current) * amount))
  }

  private func unit(_ value: Float) -> Double { min(1, max(0, Double(value))) }

  static let baseCyclesPerSecond = 0.125
  static let maximumCyclesPerSecond = 11.3
  static let sourceInterval = 1.0 / 30.0
  private static let maximumHiddenSteps = 120
}

struct SceneRenderV2NeonPulseLayer {
  let id: String
  let opacity: CGFloat
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let maximumParticlesByQuality: [String: Int]
  var controls = SceneRenderV2NeonPulseControls()
}

/// Session-seeded replay of Neon Pulse's authored 60 Hz field.
final class SceneRenderV2NeonPulseState {
  let layerID: String
  let randomSeed: UInt32
  private(set) var authoredFrame: Int64 = 0
  private(set) var elapsedSeconds = 0.0
  private(set) var motion = 0.0
  private(set) var impact = 0.0
  private(set) var colorIndex = 0
  private(set) var backgroundCenterX = 0.5
  private(set) var backgroundCenterY = 0.5
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?
  private var signalSessionID: Int64 = -1
  private var lastFlashSerial: Int64 = 0
  var controls = SceneRenderV2NeonPulseControls()

  var animationValue: Double {
    let duration = controls.animationSeconds * 2
    let phase = elapsedSeconds.truncatingRemainder(dividingBy: duration) / duration
    return phase <= 0.5 ? phase * 2 : (1 - phase) * 2
  }

  init(layerID: String, sessionSeed: UInt32) {
    self.layerID = layerID
    randomSeed = Self.nodeSeed(sessionSeed: sessionSeed, nodeID: layerID)
    updateFrameRandoms()
  }

  private init(copying previous: SceneRenderV2NeonPulseState, controls: SceneRenderV2NeonPulseControls) {
    layerID = previous.layerID; randomSeed = previous.randomSeed
    authoredFrame = previous.authoredFrame; elapsedSeconds = previous.elapsedSeconds
    motion = previous.motion; impact = previous.impact; colorIndex = previous.colorIndex
    backgroundCenterX = previous.backgroundCenterX; backgroundCenterY = previous.backgroundCenterY
    playing = previous.playing; nextStepHostTime = previous.nextStepHostTime
    signalSessionID = previous.signalSessionID; lastFlashSerial = previous.lastFlashSerial
    self.controls = controls
  }

  func copyingControls(_ next: SceneRenderV2NeonPulseControls) -> SceneRenderV2NeonPulseState {
    SceneRenderV2NeonPulseState(copying: self, controls: next)
  }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    if frame.sessionId != signalSessionID {
      signalSessionID = frame.sessionId
      lastFlashSerial = 0
    }
    let reactive = frame.available && frame.fresh && frame.musicActive
    let nextMotion = reactive ? unit(frame.dynamics[3]) : 0
    let nextImpact = reactive ? unit(frame.impact.strength) : 0
    let previousColor = colorIndex
    if reactive, frame.flash.active, frame.flash.serial > 0,
       frame.flash.serial != lastFlashSerial {
      lastFlashSerial = frame.flash.serial
      colorIndex = (colorIndex + 1) % 11
    }
    let changed = nextMotion != motion || nextImpact != impact || previousColor != colorIndex
    motion = nextMotion
    impact = nextImpact
    return changed
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    authoredFrame += Int64(due)
    elapsedSeconds += Double(due) * Self.sourceInterval
    updateFrameRandoms()
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
  }

  func particleCount(maximum: Int) -> Int {
    min(maximum, max(50, Int(motion * 200)))
  }

  private func updateFrameRandoms() {
    var random = LCG32(seed: Self.frameRandom(
      seed: randomSeed,
      itemIndex: UInt32.max,
      frame: UInt32(truncatingIfNeeded: authoredFrame)
    ))
    backgroundCenterX = random.nextDouble()
    backgroundCenterY = random.nextDouble()
  }

  private func unit(_ value: Float) -> Double { min(1, max(0, Double(value))) }

  private struct LCG32 {
    private var state: UInt32
    init(seed: UInt32) { state = seed }
    mutating func nextDouble() -> Double {
      state = 1_664_525 &* state &+ 1_013_904_223
      return Double(state) / 4_294_967_296.0
    }
  }

  static func nodeSeed(sessionSeed: UInt32, nodeID: String) -> UInt32 {
    var hash = UInt32(0x811c9dc5) ^ sessionSeed
    for byte in nodeID.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* UInt32(0x01000193)
    }
    return hash
  }

  private static func frameRandom(
    seed: UInt32,
    itemIndex: UInt32,
    frame: UInt32
  ) -> UInt32 {
    var value = seed ^ (itemIndex &* 0x9e3779b9) ^ (frame &* 0x85ebca6b)
    value ^= value >> 16
    value = value &* 0x7feb352d
    value ^= value >> 15
    value = value &* 0x846ca68b
    value ^= value >> 16
    return value
  }

  static let sourceInterval = 1.0 / 60.0
  private static let maximumHiddenSteps = 240
}
@available(iOS 15.0, *)
final class SceneSurfaceNativeOutputAllocator {
  static let capacity = 2
  private let device: MTLDevice
  private var heap: MTLHeap?
  private var textureDescriptor: MTLTextureDescriptor?
  private var allocationSize = 0
  private var byteLimit = 0

  init(device: MTLDevice) { self.device = device }

  /// Nil allocator preserves the independent output lifetime of shared V2
  /// renderers. Only a V1 component owner supplies an allocator.
  static func makeTexture(
    device: MTLDevice,
    width: Int,
    height: Int,
    allocator: SceneSurfaceNativeOutputAllocator?
  ) throws -> MTLTexture? {
    if let allocator {
      guard allocator.device.registryID == device.registryID else {
        throw AllocationError("native_program_target_device_mismatch")
      }
      return try allocator.acquire(width: width, height: height)
    }
    return device.makeTexture(descriptor: descriptor(width: width, height: height))
  }

  private static func descriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .private
    return descriptor
  }

  func acquire(width: Int, height: Int) throws -> MTLTexture {
    guard width > 0, height > 0, width <= 8192, height <= 8192 else {
      throw AllocationError("native_program_target_dimensions_invalid")
    }
    if textureDescriptor?.width != width || textureDescriptor?.height != height
        || heap == nil {
      guard heap?.usedSize ?? 0 == 0 else {
        throw AllocationError("native_program_target_backpressure")
      }
      let nextDescriptor = Self.descriptor(width: width, height: height)
      nextDescriptor.hazardTrackingMode = .tracked
      let requirement = device.heapTextureSizeAndAlign(descriptor: nextDescriptor)
      guard requirement.size > 0, requirement.align > 0 else {
        throw AllocationError("native_program_target_size_failed")
      }
      // Never alias a live texture or retain a history of resized heaps.
      heap = nil
      let alignedSize = ((requirement.size + requirement.align - 1)
        / requirement.align) * requirement.align
      byteLimit = alignedSize * Self.capacity
      let descriptor = MTLHeapDescriptor()
      descriptor.storageMode = .private
      descriptor.hazardTrackingMode = .tracked
      descriptor.size = byteLimit
      guard let created = device.makeHeap(descriptor: descriptor) else {
        throw AllocationError("native_program_target_heap_failed")
      }
      heap = created
      textureDescriptor = nextDescriptor
      allocationSize = requirement.size
    }
    guard let heap, let textureDescriptor,
          heap.usedSize <= byteLimit - allocationSize,
          let texture = heap.makeTexture(descriptor: textureDescriptor) else {
      throw AllocationError("native_program_target_backpressure")
    }
    return texture
  }

  private struct AllocationError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }
}

@available(iOS 15.0, *)
private final class SceneRenderV2NeonPulseMetalRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let backgroundPipeline: MTLRenderPipelineState
  private let particlePipeline: MTLRenderPipelineState

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("neon_pulse_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard
      let backgroundVertex = library.makeFunction(name: "neonPulseBackgroundVertex"),
      let backgroundFragment = library.makeFunction(name: "neonPulseBackgroundFragment"),
      let particleVertex = library.makeFunction(name: "neonPulseParticleVertex"),
      let particleFragment = library.makeFunction(name: "neonPulseParticleFragment")
    else { throw RendererError("neon_pulse_shader_missing") }
    backgroundPipeline = try Self.pipeline(
      device: device,
      vertex: backgroundVertex,
      fragment: backgroundFragment,
      blending: false
    )
    particlePipeline = try Self.pipeline(
      device: device,
      vertex: particleVertex,
      fragment: particleFragment,
      blending: true
    )
  }

  func render(
    width: Int,
    height: Int,
    opacity: Float,
    pointScale: Float,
    maximumParticles: Int,
    state: SceneRenderV2NeonPulseState,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard
      let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(
        device: device, width: width, height: height, allocator: outputAllocator
      ),
      let command = queue.makeCommandBuffer()
    else { throw RendererError("neon_pulse_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("neon_pulse_encoder_failed")
    }
    var viewport = SIMD2<Float>(Float(width), Float(height))
    var center = SIMD2<Float>(
      Float(state.backgroundCenterX),
      Float(state.backgroundCenterY)
    )
    var animation = Float(state.animationValue)
    var colorIndex = Int32(state.colorIndex)
    var layerOpacity = opacity
    encoder.setRenderPipelineState(backgroundPipeline)
    encoder.setFragmentBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    encoder.setFragmentBytes(&center, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
    encoder.setFragmentBytes(&animation, length: MemoryLayout<Float>.stride, index: 2)
    encoder.setFragmentBytes(&colorIndex, length: MemoryLayout<Int32>.stride, index: 3)
    encoder.setFragmentBytes(&layerOpacity, length: MemoryLayout<Float>.stride, index: 4)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

    var impact = Float(state.impact)
    var scale = pointScale * Float(state.controls.particleSize)
    var randomSeed = state.randomSeed
    var authoredFrame = UInt32(truncatingIfNeeded: state.authoredFrame)
    encoder.setRenderPipelineState(particlePipeline)
    encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    encoder.setVertexBytes(&impact, length: MemoryLayout<Float>.stride, index: 1)
    encoder.setVertexBytes(&animation, length: MemoryLayout<Float>.stride, index: 2)
    encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.stride, index: 3)
    encoder.setVertexBytes(&randomSeed, length: MemoryLayout<UInt32>.stride, index: 4)
    encoder.setVertexBytes(&authoredFrame, length: MemoryLayout<UInt32>.stride, index: 5)
    encoder.setFragmentBytes(&layerOpacity, length: MemoryLayout<Float>.stride, index: 0)
    encoder.drawPrimitives(
      type: .triangle,
      vertexStart: 0,
      vertexCount: 6,
      instanceCount: state.particleCount(maximum: maximumParticles)
    )
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("neon_pulse_gpu_failed")
    }
    return texture
  }

  private static func pipeline(
    device: MTLDevice,
    vertex: MTLFunction,
    fragment: MTLFunction,
    blending: Bool
  ) throws -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = blending
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    return try device.makeRenderPipelineState(descriptor: descriptor)
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct FullscreenOut {
      float4 position [[position]];
      float2 uv;
    };
    vertex FullscreenOut neonPulseBackgroundVertex(uint vertexID [[vertex_id]]) {
      constexpr float2 positions[6] = {
        float2(-1,-1),float2(1,-1),float2(-1,1),
        float2(-1,1),float2(1,-1),float2(1,1)
      };
      constexpr float2 uvs[6] = {
        float2(0,1),float2(1,1),float2(0,0),
        float2(0,0),float2(1,1),float2(1,0)
      };
      FullscreenOut out;
      out.position=float4(positions[vertexID],0,1);
      out.uv=uvs[vertexID];
      return out;
    }
    fragment half4 neonPulseBackgroundFragment(
      FullscreenOut in [[stage_in]],
      constant float2 &viewport [[buffer(0)]],
      constant float2 &center [[buffer(1)]],
      constant float &animation [[buffer(2)]],
      constant int &colorIndex [[buffer(3)]],
      constant float &opacity [[buffer(4)]]) {
      constexpr float3 colors[11] = {
        float3(244,67,54)/255.0,float3(255,235,59)/255.0,
        float3(0,188,212)/255.0,float3(255,193,7)/255.0,
        float3(76,175,80)/255.0,float3(33,150,243)/255.0,
        float3(255,152,0)/255.0,float3(156,39,176)/255.0,
        float3(233,30,99)/255.0,float3(205,220,57)/255.0,
        float3(63,81,181)/255.0
      };
      float2 pixel=in.uv*viewport;
      float radius=max(animation*min(viewport.x,viewport.y),0.0001);
      float amount=clamp(distance(pixel,center*viewport)/radius,0.0,1.0);
      float3 color=mix(float3(1),colors[(colorIndex+1)%11],amount);
      float alpha=mix(179.0/255.0,1.0,amount)*opacity;
      return half4(half3(color*alpha),half(alpha));
    }

    struct ParticleOut {
      float4 position [[position]];
      float2 local;
      float3 colorA [[flat]];
      float3 colorB [[flat]];
      float coverage [[flat]];
    };
    uint neonFrameRandom(uint seed,uint item,uint frame) {
      uint value=seed^item*0x9e3779b9u^frame*0x85ebca6bu;
      value^=value>>16; value*=0x7feb352du;
      value^=value>>15; value*=0x846ca68bu;
      value^=value>>16; return value;
    }
    float neonNextRandom(thread uint &state) {
      state=1664525u*state+1013904223u;
      return float(state)/4294967296.0;
    }
    vertex ParticleOut neonPulseParticleVertex(
      uint vertexID [[vertex_id]],uint instanceID [[instance_id]],
      constant float2 &viewport [[buffer(0)]],constant float &impact [[buffer(1)]],
      constant float &animation [[buffer(2)]],constant float &pointScale [[buffer(3)]],
      constant uint &seed [[buffer(4)]],constant uint &frame [[buffer(5)]]) {
      constexpr float2 positions[6] = {
        float2(-1,-1),float2(1,-1),float2(-1,1),
        float2(-1,1),float2(1,-1),float2(1,1)
      };
      constexpr float3 colors[18] = {
        float3(244,67,54)/255.0,float3(233,30,99)/255.0,
        float3(156,39,176)/255.0,float3(103,58,183)/255.0,
        float3(63,81,181)/255.0,float3(33,150,243)/255.0,
        float3(3,169,244)/255.0,float3(0,188,212)/255.0,
        float3(0,150,136)/255.0,float3(76,175,80)/255.0,
        float3(139,195,74)/255.0,float3(205,220,57)/255.0,
        float3(255,235,59)/255.0,float3(255,193,7)/255.0,
        float3(255,152,0)/255.0,float3(255,87,34)/255.0,
        float3(121,85,72)/255.0,float3(96,125,139)/255.0
      };
      uint random=neonFrameRandom(seed,instanceID,frame);
      float x=neonNextRandom(random); float y=neonNextRandom(random);
      float radius=neonNextRandom(random)*clamp(impact,0.0,1.0)*0.1*
        animation*pointScale;
      random=1664525u*random+1013904223u; uint colorA=random;
      random=1664525u*random+1013904223u; uint colorB=random;
      float extent=max(radius,0.5);
      float2 local=positions[vertexID];
      float2 center=float2(x*2.0-1.0,1.0-y*2.0);
      ParticleOut out;
      out.position=float4(center+local*extent*2.0/max(viewport,float2(1)),0,1);
      out.local=local;
      out.colorA=colors[colorA%18u]; out.colorB=colors[colorB%18u];
      out.coverage=clamp(radius*2.0,0.0,1.0);
      return out;
    }
    fragment half4 neonPulseParticleFragment(
      ParticleOut in [[stage_in]],constant float &opacity [[buffer(0)]]) {
      float distanceToCenter=length(in.local);
      if(distanceToCenter>1.0) discard_fragment();
      float gradient=clamp(distanceToCenter,0.0,1.0);
      float alpha=(1.0-gradient)*in.coverage*opacity;
      float3 color=mix(in.colorA,in.colorB,gradient);
      return half4(half3(color*alpha),half(alpha));
    }
  """#
}

struct SceneRenderV2EmbeddedScreenPoint: Equatable {
  let x: Double
  let y: Double
}

struct SceneRenderV2EmbeddedScreenLayer {
  let id: String
  let source: CIImage
  let opacity: CGFloat
  let width: CGFloat
  let height: CGFloat
  let offsetX: CGFloat
  let offsetY: CGFloat
  let scale: CGFloat
  let rotation: CGFloat
  let flipped: Bool
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let ringCountsByQuality: [String: Int]
  let rayCountsByQuality: [String: Int]
  let spectrumSamplesByQuality: [String: Int]
  let topLeft: SceneRenderV2EmbeddedScreenPoint
  let topRight: SceneRenderV2EmbeddedScreenPoint
  let bottomRight: SceneRenderV2EmbeddedScreenPoint
  let bottomLeft: SceneRenderV2EmbeddedScreenPoint
  let mode: String
  let backgroundARGB: UInt32
  let primaryARGB: UInt32
  let accentARGB: UInt32
  let idleOpacity: Double
  let glow: Double
  let lineWidth: Double
  let flowGain: Double
  let bassGain: Double
  let bodyGain: Double
  let sparkGain: Double
  let attackSeconds: Double
  let releaseSeconds: Double
}

/// Stateful, bounded replay of the embedded-screen visual authority. The
/// state is retained across quality changes so audio response and phase never
/// restart while the renderer reduces cost.
final class SceneRenderV2EmbeddedScreenState {
  let layerID: String
  private(set) var bass = 0.0
  private(set) var body = 0.0
  private(set) var spark = 0.0
  private(set) var flow = 0.0
  private(set) var level = 0.0
  private(set) var phaseSeconds = 0.0
  private(set) var spectrum = Array(repeating: Float(0), count: 17)
  private var signalSessionID: Int64 = -1
  private var lastAudioTimestampMicros: Int64 = -1

  init(layerID: String) { self.layerID = layerID }

  func consume(
    _ frame: SceneRenderSignalFrameV2,
    layer: SceneRenderV2EmbeddedScreenLayer
  ) -> Bool {
    let previous = [bass, body, spark, flow, level, phaseSeconds]
    let previousSpectrum = spectrum
    if frame.sessionId != signalSessionID {
      signalSessionID = frame.sessionId
      lastAudioTimestampMicros = -1
      bass = 0
      body = 0
      spark = 0
      flow = 0
      level = 0
      spectrum = Array(repeating: 0, count: 17)
    }
    let delta: Double = lastAudioTimestampMicros < 0
      ? 0
      : min(
        0.1,
        max(0, Double(frame.audioTimestampMicros - lastAudioTimestampMicros) / 1_000_000)
      )
    lastAudioTimestampMicros = frame.audioTimestampMicros
    let reactive = frame.available && frame.fresh && frame.musicActive
    bass = follow(
      bass,
      target: reactive ? unit(frame.channels[0]) * layer.bassGain : 0,
      delta: delta,
      layer: layer
    )
    body = follow(
      body,
      target: reactive ? unit(frame.channels[1]) * layer.bodyGain : 0,
      delta: delta,
      layer: layer
    )
    spark = follow(
      spark,
      target: reactive ? unit(frame.channels[2]) * layer.sparkGain : 0,
      delta: delta,
      layer: layer
    )
    flow = follow(
      flow,
      target: reactive ? unit(frame.channels[3]) * layer.flowGain : 0,
      delta: delta,
      layer: layer
    )
    level = follow(
      level,
      target: reactive ? unit(frame.dynamics[2]) : 0,
      delta: delta,
      layer: layer
    )
    phaseSeconds = Double(frame.audioTimestampMicros) / 1_000_000
    let source = reactive ? frame.smoothedSpectrum : []
    for index in spectrum.indices {
      let sourceIndex = source.isEmpty ? 0 : Int(
        (Double(index) / Double(spectrum.count - 1) * Double(source.count - 1)).rounded(.down)
      )
      spectrum[index] = source.isEmpty ? 0 : min(1, max(0, source[sourceIndex]))
    }
    return previous[0] != bass || previous[1] != body || previous[2] != spark ||
      previous[3] != flow || previous[4] != level || previous[5] != phaseSeconds ||
      previousSpectrum != spectrum
  }

  private func follow(
    _ current: Double,
    target rawTarget: Double,
    delta: Double,
    layer: SceneRenderV2EmbeddedScreenLayer
  ) -> Double {
    let target = min(1, max(0, rawTarget))
    guard delta > 0, current != target else { return current }
    let seconds = target > current ? layer.attackSeconds : layer.releaseSeconds
    let amount = 1 - Foundation.exp(-delta / max(0.001, seconds))
    return min(1, max(0, current + (target - current) * amount))
  }

  private func unit(_ value: Float) -> Double { min(1, max(0, Double(value))) }
}

@available(iOS 15.0, *)
private final class SceneRenderV2EmbeddedScreenMetalRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("embedded_screen_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard
      let vertex = library.makeFunction(name: "embeddedScreenVertex"),
      let fragment = library.makeFunction(name: "embeddedScreenFragment")
    else { throw RendererError("embedded_screen_shader_missing") }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  func render(
    width: Int,
    height: Int,
    corners: [SIMD2<Float>],
    layer: SceneRenderV2EmbeddedScreenLayer,
    state: SceneRenderV2EmbeddedScreenState,
    quality: String,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard
      corners.count == 4,
      let ringCount = layer.ringCountsByQuality[quality],
      let rayCount = layer.rayCountsByQuality[quality],
      let spectrumSamples = layer.spectrumSamplesByQuality[quality]
    else { throw RendererError("embedded_screen_quality_invalid") }
    guard
      let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(
        device: device, width: width, height: height, allocator: outputAllocator
      ),
      let command = queue.makeCommandBuffer()
    else { throw RendererError("embedded_screen_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("embedded_screen_encoder_failed")
    }
    var viewport = SIMD2<Float>(Float(width), Float(height))
    let mutableCorners = corners
    let colors = [
      Self.rgb(layer.backgroundARGB),
      Self.rgb(layer.primaryARGB),
      Self.rgb(layer.accentARGB),
    ]
    var style = SIMD4<Float>(
      Float(layer.idleOpacity),
      Float(layer.glow),
      Float(layer.lineWidth),
      Float(layer.opacity)
    )
    var response = SIMD4<Float>(
      Float(state.bass),
      Float(state.body),
      Float(state.spark),
      Float(state.flow)
    )
    var energyAndTime = SIMD2<Float>(Float(state.level), Float(state.phaseSeconds))
    var complexity = SIMD4<Int32>(
      layer.mode == "prismaticSpectrumField" ? 1 : 0,
      Int32(ringCount),
      Int32(rayCount),
      Int32(spectrumSamples)
    )
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    mutableCorners.withUnsafeBytes {
      encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1)
    }
    colors.withUnsafeBytes {
      encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2)
    }
    encoder.setFragmentBytes(&style, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
    encoder.setFragmentBytes(&response, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
    encoder.setFragmentBytes(
      &energyAndTime,
      length: MemoryLayout<SIMD2<Float>>.stride,
      index: 5
    )
    encoder.setFragmentBytes(
      &complexity,
      length: MemoryLayout<SIMD4<Int32>>.stride,
      index: 6
    )
    state.spectrum.withUnsafeBytes {
      encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 7)
    }
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("embedded_screen_gpu_failed")
    }
    return texture
  }

  private static func rgb(_ argb: UInt32) -> SIMD3<Float> {
    SIMD3<Float>(
      Float((argb >> 16) & 0xff) / 255,
      Float((argb >> 8) & 0xff) / 255,
      Float(argb & 0xff) / 255
    )
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct EmbeddedOut { float4 position [[position]]; float2 uv; };
    vertex EmbeddedOut embeddedScreenVertex(uint vertexID [[vertex_id]]) {
      constexpr float2 positions[6] = {
        float2(-1,-1),float2(1,-1),float2(-1,1),
        float2(-1,1),float2(1,-1),float2(1,1)
      };
      constexpr float2 uvs[6] = {
        float2(0,1),float2(1,1),float2(0,0),
        float2(0,0),float2(1,1),float2(1,0)
      };
      EmbeddedOut out;
      out.position=float4(positions[vertexID],0,1);
      out.uv=uvs[vertexID];
      return out;
    }
    float2 embeddedInverseBilinear(float2 p,constant float2 *corner) {
      float2 a=corner[0]; float2 b=corner[1]-corner[0];
      float2 c=corner[3]-corner[0];
      float2 d=corner[0]-corner[1]-corner[3]+corner[2];
      float2 q=clamp((p-a)/max(abs(b+c),float2(0.0001)),0.0,1.0);
      for(int i=0;i<6;i++) {
        float2 error=a+b*q.x+c*q.y+d*q.x*q.y-p;
        float2 du=b+d*q.y; float2 dv=c+d*q.x;
        float determinant=du.x*dv.y-du.y*dv.x;
        if(abs(determinant)<0.0000001) break;
        q-=float2(
          (error.x*dv.y-error.y*dv.x)/determinant,
          (du.x*error.y-du.y*error.x)/determinant
        );
      }
      return q;
    }
    float embeddedEdge(float2 a,float2 b,float2 p) {
      float2 edge=b-a; float2 relative=p-a;
      return edge.x*relative.y-edge.y*relative.x;
    }
    bool embeddedInsideQuad(float2 p,constant float2 *corner) {
      constexpr float epsilon=0.00001;
      float e0=embeddedEdge(corner[0],corner[1],p);
      float e1=embeddedEdge(corner[1],corner[2],p);
      float e2=embeddedEdge(corner[2],corner[3],p);
      float e3=embeddedEdge(corner[3],corner[0],p);
      bool nonnegative=e0>=-epsilon&&e1>=-epsilon&&e2>=-epsilon&&e3>=-epsilon;
      bool nonpositive=e0<=epsilon&&e1<=epsilon&&e2<=epsilon&&e3<=epsilon;
      return nonnegative||nonpositive;
    }
    float embeddedSpectrumAt(
      float normalized,constant float *spectrum,int spectrumSamples
    ) {
      float maximum=float(max(spectrumSamples-1,1));
      int reduced=int(round(clamp(normalized,0.0,1.0)*maximum));
      int source=int(round(float(reduced)/maximum*16.0));
      return clamp(spectrum[clamp(source,0,16)],0.0,1.0);
    }
    float embeddedMeanSpectrum(constant float *spectrum,int first,int lastExclusive) {
      float sum=0; int count=0;
      for(int index=0;index<17;index++) if(index>=first&&index<lastExclusive) {
        sum+=clamp(spectrum[index],0.0,1.0); count++;
      }
      return count==0?0:sum/float(count);
    }
    float3 embeddedPrismaticHaloGeometry(
      float2 screenUV,float2 core,float2 viewport,constant float2 *corners,
      float energy,float bassDrive,float sparkBurst
    ) {
      float2 top=mix(corners[0],corners[1],core.x);
      float2 bottom=mix(corners[3],corners[2],core.x);
      float2 coreScreenUV=mix(top,bottom,core.y);
      float screenScale=max(length((corners[1]-corners[0])*viewport),
        length((corners[3]-corners[0])*viewport));
      float distanceToCore=length((screenUV-coreScreenUV)*viewport);
      float fieldRadius=screenScale*
        (0.12+energy*0.62+bassDrive*0.38+sparkBurst*0.24);
      float coreRadius=max(1.5,screenScale*
        (0.026+energy*0.10+bassDrive*0.13+sparkBurst*0.055));
      return float3(distanceToCore,fieldRadius,coreRadius);
    }
    float4 embeddedPrismatic(
      float2 uv,float2 screenUV,float2 viewport,constant float2 *corners,
      constant float3 *colors,float4 style,float4 response,
      float2 energyTime,int4 complexity,constant float *spectrum
    ) {
      constexpr float pi=3.14159265358979323846;
      constexpr float tau=6.28318530717958647692;
      float bass= response.x, body=response.y, spark=response.z, flow=response.w;
      float level=energyTime.x, phaseSeconds=energyTime.y;
      float bassDrive=clamp((bass-0.18)/0.65,0.0,1.0);
      float bodyDrive=clamp((body-0.12)/0.58,0.0,1.0);
      float sparkBurst=clamp((spark-0.06)/0.30,0.0,1.0);
      float levelDrive=clamp((level-0.08)/0.75,0.0,1.0);
      float energy=clamp(0.34*bodyDrive+0.38*bassDrive+0.28*levelDrive,0.0,1.0);
      float3 cyan=mix(colors[1],float3(0,0.964706,1),0.74);
      float3 magenta=mix(colors[2],float3(1,0.121569,0.658824),0.72);
      float3 amber=float3(1,0.811765,0.290196);
      float low=embeddedMeanSpectrum(spectrum,0,5);
      float middle=embeddedMeanSpectrum(spectrum,5,11);
      float high=embeddedMeanSpectrum(spectrum,11,17);
      float3 active=mix(cyan,magenta,middle*0.72+high*0.28);
      float motion=phaseSeconds*energy;
      float2 core=float2(0.28+sin(motion*0.83)*flow*0.035,
        0.52+cos(motion*0.67)*flow*0.045);
      float3 color=mix(colors[0],float3(0.003922,0.011765,0.039216),0.76);
      float diagonal=clamp((uv.x+uv.y)*0.5,0.0,1.0);
      color+=mix(cyan,magenta,diagonal)*style.x*0.045;
      float2 delta=uv-core;
      float3 halo=embeddedPrismaticHaloGeometry(screenUV,core,viewport,corners,
        energy,bassDrive,sparkBurst);
      float field=1-smoothstep(0.0,max(halo.y,0.001),halo.x);
      color+=mix(cyan,active,field)*field*energy*0.60;
      color+=amber*pow(field,5.0)*energy*(0.24+low*0.20);
      float coreGlow=1-smoothstep(0.0,max(halo.z,0.001),halo.x);
      color+=mix(active,float3(1),pow(coreGlow,2.0))*coreGlow*
        (0.08+energy*0.82+sparkBurst*0.42);
      float angle=atan2(delta.y/0.72,delta.x/1.28);
      float ellipseRadius=length(float2(delta.x/1.28,delta.y/0.72));
      float normalizedAngle=fract(angle/tau+1.0);
      float sample=embeddedSpectrumAt(normalizedAngle,spectrum,complexity.w);
      for(int ring=0;ring<4;ring++) {
        if(ring>=complexity.y||energy<=0.015) continue;
        float radius=0.045+energy*0.075+bassDrive*0.095+sparkBurst*0.085+
          float(ring)*(0.052+bodyDrive*0.023);
        float deformation=0.025+flow*0.09+high*0.025+sparkBurst*0.07;
        float wobble=1+sin(angle*3+motion*(0.55+flow*0.8))*deformation*
          (0.28+sample*0.72);
        float stroke=style.z*(0.48+energy*0.72+sparkBurst*1.35);
        float line=1-smoothstep(stroke,stroke*2.2,abs(ellipseRadius-radius*wobble));
        float glow=1-smoothstep(stroke*2,stroke*(6.2+style.y*4),
          abs(ellipseRadius-radius*wobble));
        float3 ringColor=ring==0?float3(1):(ring==1?amber:(ring==2?magenta:cyan));
        float alpha=clamp(energy*(0.26+float(ring)*0.07)+
          sparkBurst*(ring==0?0.64:0.24),0.0,1.0);
        color+=ringColor*alpha*(line+glow*0.34);
      }
      if(sparkBurst>0.015&&complexity.z>0) for(int ray=0;ray<10;ray++) {
        if(ray>=complexity.z) continue;
        float rayAngle=float(ray)/float(complexity.z)*tau+motion*0.16;
        float2 direction=float2(cos(rayAngle),sin(rayAngle)*0.68);
        float along=dot(delta,normalize(direction));
        float perpendicular=abs(delta.x*direction.y-delta.y*direction.x)/
          max(length(direction),0.0001);
        float inner=0.05+energy*0.08;
        float outer=inner+0.055+sparkBurst*0.30*((ray&1)==0?1.0:0.58);
        float rayMask=step(inner,along)*step(along,outer)*
          (1-smoothstep(0.003,0.014,perpendicular));
        color+=float3(1)*rayMask*sparkBurst*0.92;
      }
      color+=active*(bassDrive*bassDrive*0.08+sparkBurst*sparkBurst*0.20);
      return float4(clamp(color,0.0,1.0),1);
    }
    float4 embeddedCenteredWave(
      float2 uv,constant float3 *colors,float4 style,float4 response,
      float2 energyTime,int4 complexity,constant float *spectrum
    ) {
      constexpr float pi=3.14159265358979323846;
      float energy=clamp(0.48*response.y+0.34*response.x+0.18*energyTime.x,0.0,1.0);
      float amplitude=0.045+energy*0.25+response.w*0.055;
      float pulse=1+response.x*0.16;
      float centered=(uv.x-0.5)/pulse;
      float envelope=exp(-abs(centered)*(2-response.w*0.45));
      float carrier=cos(centered*pi*(5.2-response.y*0.8));
      float spectral=0.64+embeddedSpectrumAt(uv.x,spectrum,complexity.w)*0.62;
      float waveY=0.5-carrier*envelope*amplitude*spectral;
      float distanceToWave=abs(uv.y-clamp(waveY,0.10,0.90));
      float stroke=max(style.z,0.002);
      float line=1-smoothstep(stroke,stroke*2,distanceToWave);
      float glow=1-smoothstep(stroke*2,stroke*(8+style.y*5),distanceToWave);
      float3 color=colors[0]*0.97;
      float3 active=mix(colors[1],colors[2],response.z*0.72);
      color+=active*(line+glow*0.28)*clamp(style.x+energy*0.28,0.0,1.0);
      return float4(clamp(color,0.0,1.0),1);
    }
    fragment half4 embeddedScreenFragment(
      EmbeddedOut in [[stage_in]],constant float2 &viewport [[buffer(0)]],
      constant float2 *corners [[buffer(1)]],constant float3 *colors [[buffer(2)]],
      constant float4 &style [[buffer(3)]],constant float4 &response [[buffer(4)]],
      constant float2 &energyTime [[buffer(5)]],constant int4 &complexity [[buffer(6)]],
      constant float *spectrum [[buffer(7)]]) {
      if(!embeddedInsideQuad(in.uv,corners)) discard_fragment();
      float2 uv=embeddedInverseBilinear(in.uv,corners);
      if(any(uv<0.0)||any(uv>1.0)) discard_fragment();
      float4 value=complexity.x==1
        ? embeddedPrismatic(uv,in.uv,viewport,corners,colors,style,response,
            energyTime,complexity,spectrum)
        : embeddedCenteredWave(uv,colors,style,response,energyTime,complexity,spectrum);
      float alpha=clamp(style.w,0.0,1.0);
      return half4(half3(value.rgb*alpha),half(alpha));
    }
  """#
}

struct SceneRenderV2WaveformLayer {
  let id: String
  let opacity: Double
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
  let sampleCountsByQuality: [String: Int]
  let spectralNodeCountsByQuality: [String: Int]
  let glowPassesByQuality: [String: Int]
  let idleVisibility: Double
  let zeroThreshold: Double
  let maximumDisplacementHeightFraction: Double
  let maximumDisplacementWidthFraction: Double
  let outerARGB: UInt32
  let peakARGB: UInt32
  let hotCoreARGB: UInt32
  let innerARGB: UInt32
  let coreARGB: UInt32
  let responseSeconds: [Double]
}

/// Exact, bounded replay of MusicWaveformField. Quality transitions retain this
/// authority; only sampling density, glow count and cadence change.
final class SceneRenderV2WaveformState {
  static let sampleCount = 127
  static let spectralNodeCount = 15
  private static let centerSample = sampleCount / 2
  private static let tau = Double.pi * 2

  let layerID: String
  private(set) var samples = Array(repeating: Float(0), count: sampleCount)
  private var targets = Array(repeating: Float(0), count: sampleCount)
  private var spectralNodes = Array(repeating: Float(0), count: spectralNodeCount)
  private(set) var lineEnergy = 0.0
  private(set) var peakAmplitude = 0.0
  private(set) var lineVisibility = 0.0
  private(set) var impactLight = 0.0

  private var bass = 0.0
  private var body = 0.0
  private var spark = 0.0
  private var flow = 0.0
  private var level = 0.0
  private var signalSessionID: Int64 = -1
  private var lastAudioTimestampMicros: Int64 = -1
  private var lastEventSerials = Array(repeating: Int64(-1), count: 4)
  private var excitation = 0.0
  private var width = 0.155
  private var targetWidth = 0.155
  private var wavelength = 0.25
  private var targetWavelength = 0.25
  private var complexity = 0.10
  private var targetComplexity = 0.10
  private var shapeAccent = 0.0
  private var adaptiveDrive = 0.0
  private var transientDrive = 0.0
  private var adaptiveDriveInitialized = false
  private var standingPhase = 0.0
  private var standingPulse = 0.0
  private var accentWidth = 0.155
  private var accentWavelength = 0.25
  private var accentComplexity = 0.10

  init(layerID: String) { self.layerID = layerID }

  func consume(
    _ frame: SceneRenderSignalFrameV2,
    layer: SceneRenderV2WaveformLayer
  ) -> Bool {
    let oldSamples = samples
    let oldEnergy = lineEnergy
    let oldVisibility = lineVisibility
    let oldImpact = impactLight
    if frame.sessionId != signalSessionID {
      signalSessionID = frame.sessionId
      reset()
    }
    let delta = lastAudioTimestampMicros < 0
      ? 0
      : min(
        0.1,
        max(0, Double(frame.audioTimestampMicros - lastAudioTimestampMicros) / 1_000_000)
      )
    lastAudioTimestampMicros = frame.audioTimestampMicros
    let reactive = frame.available && frame.fresh && frame.musicActive

    updateTransientDrive(
      delta: delta,
      active: reactive,
      bassValue: unit(frame.channels[0]),
      bodyValue: unit(frame.channels[1]),
      levelValue: unit(frame.dynamics[2])
    )
    updateStandingPulse(
      delta: delta,
      active: reactive,
      bodyValue: unit(frame.channels[1]),
      flowValue: unit(frame.channels[3]),
      levelValue: unit(frame.dynamics[2]),
      rhythmPhase: unit(frame.rhythm[1]),
      rhythmConfidence: max(unit(frame.rhythm[2]), unit(frame.rhythm[3]))
    )
    bass = responseFollow(
      bass, reactive ? unit(frame.channels[0]) : 0, delta,
      layer.responseSeconds[0], layer.responseSeconds[1]
    )
    body = responseFollow(
      body, reactive ? unit(frame.channels[1]) : 0, delta,
      layer.responseSeconds[2], layer.responseSeconds[3]
    )
    spark = responseFollow(
      spark, reactive ? unit(frame.channels[2]) : 0, delta,
      layer.responseSeconds[4], layer.responseSeconds[5]
    )
    flow = responseFollow(
      flow, reactive ? unit(frame.channels[3]) : 0, delta,
      layer.responseSeconds[6], layer.responseSeconds[7]
    )
    level = responseFollow(
      level, reactive ? unit(frame.dynamics[2]) : 0, delta,
      layer.responseSeconds[8], layer.responseSeconds[9]
    )

    if reactive {
      rebuildSpectralModifiers(frame.smoothedSpectrum)
      updateDeformation(delta: delta, frame: frame)
      let musicalDrive = max(level, max(bass * 0.90, body * 0.72))
      rebuildTargets(
        displacementGain: min(
          1,
          max(
            0,
            musicalDrive * (0.16 + standingPulse * 0.86) + shapeAccent * 0.20 +
              transientDrive * 0.34 + excitation * 0.72
          )
        )
      )
    } else {
      excitation = follow(excitation, 0, delta, 0.01, 0.12)
      impactLight = follow(impactLight, 0, delta, 0.01, 0.16)
      spectralNodes = Array(repeating: 1, count: Self.spectralNodeCount)
      rebuildTargets(displacementGain: 0)
    }
    followTargets(delta: delta, zeroThreshold: layer.zeroThreshold)
    lineEnergy = min(
      1,
      max(
        0,
        level * 0.46 + excitation * 0.34 + impactLight * 0.12 +
          transientDrive * 0.20 + standingPulse * 0.12 + spark * 0.08
      )
    )
    lineVisibility = follow(
      lineVisibility,
      reactive ? min(1, max(0, 0.72 + lineEnergy * 0.28)) : layer.idleVisibility,
      delta,
      0.035,
      0.20
    )
    return oldEnergy != lineEnergy || oldVisibility != lineVisibility ||
      oldImpact != impactLight || oldSamples != samples
  }

  private func updateStandingPulse(
    delta: Double,
    active: Bool,
    bodyValue: Double,
    flowValue: Double,
    levelValue: Double,
    rhythmPhase: Double,
    rhythmConfidence: Double
  ) {
    guard active else {
      standingPhase = 0
      standingPulse = follow(standingPulse, 0, delta, 0.02, 0.10)
      return
    }
    let target: Double
    if rhythmConfidence >= 0.35 {
      let phase = rhythmPhase - Foundation.floor(rhythmPhase)
      let distance = min(phase, 1 - phase)
      target = Foundation.exp(-0.5 * Foundation.pow(distance / 0.16, 2)) *
        (0.62 + rhythmConfidence * 0.38)
    } else {
      let rate = 0.58 + flowValue * 0.56 + bodyValue * 0.34
      standingPhase = (standingPhase + delta * rate).truncatingRemainder(dividingBy: 1)
      let wave = 0.5 - 0.5 * Foundation.cos(Self.tau * standingPhase)
      target = min(
        1,
        max(
          0,
          0.08 + Foundation.pow(wave, 1.25) * 0.92 *
            (0.70 + max(levelValue, bodyValue) * 0.30)
        )
      )
    }
    standingPulse = follow(standingPulse, target, delta, 0.055, 0.085)
  }

  private func updateTransientDrive(
    delta: Double,
    active: Bool,
    bassValue: Double,
    bodyValue: Double,
    levelValue: Double
  ) {
    guard active else {
      adaptiveDriveInitialized = false
      adaptiveDrive = follow(adaptiveDrive, 0, delta, 0.10, 0.42)
      transientDrive = follow(transientDrive, 0, delta, 0.01, 0.12)
      return
    }
    let drive = max(levelValue, min(1, max(0, bassValue * 0.82 + bodyValue * 0.18)))
    guard adaptiveDriveInitialized else {
      adaptiveDriveInitialized = true
      adaptiveDrive = drive
      transientDrive = 0
      return
    }
    adaptiveDrive = follow(adaptiveDrive, drive, delta, 0.72, 1.10)
    let target = min(
      1,
      max(
        0,
        max(0, drive - adaptiveDrive) * 4.2 +
          max(0, drive - max(level, bass * 0.88)) * 2.4
      )
    )
    transientDrive = follow(transientDrive, target, delta, 0.014, 0.16)
  }

  private func rebuildSpectralModifiers(_ spectrum: [Float]) {
    guard !spectrum.isEmpty else {
      spectralNodes = Array(repeating: 1, count: Self.spectralNodeCount)
      return
    }
    let average = spectrum.reduce(0) { $0 + unit($1) } / Double(spectrum.count)
    let last = spectrum.count - 1
    for node in spectralNodes.indices {
      let normalized = Double(node) / Double(spectralNodes.count - 1)
      let source = min(
        Double(last),
        max(0, 2 + Foundation.pow(normalized, 1.18) * Double(max(0, last - 2)))
      )
      let lower = Int(Foundation.floor(source))
      let upper = min(last, lower + 1)
      let magnitude = unit(spectrum[lower]) * (1 - source + Double(lower)) +
        unit(spectrum[upper]) * (source - Double(lower))
      spectralNodes[node] = Float(
        min(1.36, max(0.46, 0.78 + (magnitude - average) * 0.90 + magnitude * 0.30))
      )
    }
    spectralNodes[0] = 1
  }

  private func updateDeformation(delta: Double, frame: SceneRenderSignalFrameV2) {
    var low = max(unit(frame.onsets[0]), bass * unit(frame.onsets[3]))
    var middle = max(unit(frame.onsets[1]), body * unit(frame.onsets[3]))
    var high = max(unit(frame.onsets[2]), spark * unit(frame.onsets[3]))
    let onset = max(unit(frame.onsets[3]), max(low * 0.92, max(middle * 0.84, high * 0.72)))
    let continuousWidth = min(
      0.285,
      max(
        0.115,
        0.125 + bass * 0.090 + flow * 0.018 - spark * 0.012 +
          transientDrive * 0.075 + standingPulse * 0.055
      )
    )
    let continuousWavelength = min(
      0.46,
      max(
        0.175,
        0.235 + bass * 0.125 + body * 0.025 - spark * 0.055 +
          transientDrive * 0.145 + standingPulse * 0.130
      )
    )
    let continuousComplexity = min(
      0.72,
      max(
        0.055,
        0.055 + body * 0.20 + Foundation.pow(spark, 1.6) * 0.68 -
          transientDrive * 0.24 - standingPulse * 0.12
      )
    )
    let events = [frame.impact, frame.accent, frame.beat, frame.flash]
    let gains = [1.0, 0.92, 1.0, 0.82]
    var selected: SceneRenderSignalEventV2?
    var selectedStrength = 0.0
    for (index, event) in events.enumerated() where event.serial > lastEventSerials[index] {
      lastEventSerials[index] = event.serial
      let strength = event.active ? unit(event.strength) * gains[index] : 0
      if strength >= selectedStrength {
        selected = event
        selectedStrength = strength
      }
    }
    let impactDrive = min(1, max(0, selectedStrength))
    switch selected?.band {
    case .some(.low): low = max(low, impactDrive)
    case .some(.body): middle = max(middle, impactDrive)
    case .some(.high): high = max(high, impactDrive)
    case .some(.broadband):
      low = max(low, impactDrive * 0.72)
      middle = max(middle, impactDrive)
      high = max(high, impactDrive * 0.62)
    case .some(.none), nil: middle = max(middle, impactDrive * 0.82)
    }
    var eventStrength = max(onset, transientDrive)
    if impactDrive > 0 { eventStrength = max(eventStrength, 0.42 + impactDrive * 0.58) }
    let impactEvent = Foundation.pow(min(1, max(0, (eventStrength - 0.45) / 0.55)), 2.2)
    let onsetEvent = Foundation.pow(min(1, max(0, (onset - 0.10) / 0.62)), 1.45)
    let shaped = max(impactEvent, onsetEvent)
    if shaped > 0 {
      let total = max(0.001, low + middle + high)
      let lowShare = low / total
      let middleShare = middle / total
      let highShare = high / total
      accentWidth = min(
        0.31,
        max(0.14, 0.145 + lowShare * 0.17 + middleShare * 0.075 + highShare * 0.018)
      )
      accentWavelength = min(
        0.46,
        max(0.13, 0.125 + lowShare * 0.34 + middleShare * 0.13 + highShare * 0.012)
      )
      accentComplexity = min(
        0.96,
        max(0.06, 0.06 + middleShare * 0.42 + highShare * 0.88)
      )
    }
    shapeAccent = follow(
      shapeAccent,
      shaped > 0 ? 0.28 + shaped * 0.72 : 0,
      delta,
      0.018,
      0.06
    )
    targetWidth = continuousWidth + (accentWidth - continuousWidth) * shapeAccent
    targetWavelength = continuousWavelength +
      (accentWavelength - continuousWavelength) * shapeAccent
    targetComplexity = continuousComplexity +
      (accentComplexity - continuousComplexity) * shapeAccent
    excitation = follow(excitation, shaped, delta, 0.010, 0.06)
    impactLight = follow(
      impactLight,
      max(impactDrive, max(shaped, transientDrive * 0.82)),
      delta,
      0.012,
      0.24
    )
    width = follow(width, targetWidth, delta, 0.045, 0.18)
    wavelength = follow(wavelength, targetWavelength, delta, 0.045, 0.20)
    complexity = follow(complexity, targetComplexity, delta, 0.025, 0.16)
  }

  private func rebuildTargets(displacementGain: Double) {
    for index in targets.indices {
      let signedDistance = Double(index - Self.centerSample) / Double(Self.sampleCount - 1)
      let absoluteDistance = abs(signedDistance)
      let phase = Self.tau * signedDistance / wavelength
      let primaryEnvelope = Foundation.exp(
        -0.5 * absoluteDistance * absoluteDistance / (width * width)
      )
      let tailWidth = min(0.48, width * 2.15)
      let tailEnvelope = Foundation.exp(
        -0.5 * absoluteDistance * absoluteDistance / (tailWidth * tailWidth)
      )
      let envelope = (primaryEnvelope + tailEnvelope * 0.075) / 1.075
      let lobePosition = absoluteDistance / max(0.001, wavelength * 0.5)
      let lower = min(
        spectralNodes.count - 1,
        max(0, Int(Foundation.floor(lobePosition)))
      )
      let upper = min(spectralNodes.count - 1, lower + 1)
      let blend = lobePosition - Foundation.floor(lobePosition)
      let modifier = Double(spectralNodes[lower]) * (1 - blend) +
        Double(spectralNodes[upper]) * blend
      let harmonic = Foundation.cos(phase) * (1 - complexity * 0.34) +
        Foundation.cos(phase * 2) * complexity * 0.23 +
        Foundation.cos(phase * 3) * complexity * 0.11
      targets[index] = Float(
        min(
          1,
          max(
            -1,
            harmonic * envelope * modifier * displacementGain /
              (1 + complexity * 0.03)
          )
        )
      )
    }
  }

  private func followTargets(delta: Double, zeroThreshold: Double) {
    var peak = 0.0
    for index in samples.indices {
      let current = Double(samples[index])
      let target = Double(targets[index])
      let duration = abs(target) > abs(current) ? 0.018 : 0.032
      let next = current + (target - current) * (1 - Foundation.exp(-delta / duration))
      let sample = abs(next) < zeroThreshold ? 0 : next
      samples[index] = Float(sample)
      peak = max(peak, abs(sample))
    }
    peakAmplitude = peak
  }

  private func reset() {
    samples = Array(repeating: 0, count: Self.sampleCount)
    targets = Array(repeating: 0, count: Self.sampleCount)
    spectralNodes = Array(repeating: 0, count: Self.spectralNodeCount)
    lastAudioTimestampMicros = -1
    lastEventSerials = Array(repeating: -1, count: 4)
    bass = 0; body = 0; spark = 0; flow = 0; level = 0
    lineEnergy = 0; peakAmplitude = 0; lineVisibility = 0
    excitation = 0; impactLight = 0
    width = 0.155; targetWidth = 0.155
    wavelength = 0.25; targetWavelength = 0.25
    complexity = 0.10; targetComplexity = 0.10; shapeAccent = 0
    adaptiveDrive = 0; transientDrive = 0; adaptiveDriveInitialized = false
    standingPhase = 0; standingPulse = 0
    accentWidth = 0.155; accentWavelength = 0.25; accentComplexity = 0.10
  }

  private func responseFollow(
    _ current: Double,
    _ target: Double,
    _ delta: Double,
    _ attack: Double,
    _ release: Double
  ) -> Double { follow(current, target, delta, attack, release) }

  private func follow(
    _ current: Double,
    _ target: Double,
    _ delta: Double,
    _ attack: Double,
    _ release: Double
  ) -> Double {
    guard delta > 0, current != target else { return current }
    let duration = target > current ? attack : release
    let next = current + (target - current) * (1 - Foundation.exp(-delta / duration))
    return abs(next - target) < 0.0001 ? target : next
  }

  private func unit(_ value: Float) -> Double { min(1, max(0, Double(value))) }
}

@available(iOS 15.0, *)
private final class SceneRenderV2WaveformMetalRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("waveform_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard
      let vertex = library.makeFunction(name: "waveformVertex"),
      let fragment = library.makeFunction(name: "waveformFragment")
    else { throw RendererError("waveform_shader_missing") }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  func render(
    width: Int,
    height: Int,
    layer: SceneRenderV2WaveformLayer,
    state: SceneRenderV2WaveformState,
    quality: String,
    pointScale: Float,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard
      let sampleCount = layer.sampleCountsByQuality[quality],
      let glowPasses = layer.glowPassesByQuality[quality]
    else { throw RendererError("waveform_quality_invalid") }
    guard
      let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(
        device: device, width: width, height: height, allocator: outputAllocator
      ),
      let command = queue.makeCommandBuffer()
    else { throw RendererError("waveform_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("waveform_encoder_failed")
    }
    var viewport = SIMD2<Float>(Float(width), Float(height))
    let metrics = [
      Float(layer.opacity), Float(state.lineEnergy), Float(state.peakAmplitude),
      Float(state.impactLight), Float(state.lineVisibility),
      Float(layer.maximumDisplacementHeightFraction),
      Float(layer.maximumDisplacementWidthFraction),
      pointScale,
    ]
    var counts = SIMD2<Int32>(Int32(sampleCount), Int32(glowPasses))
    let colors = [
      Self.rgb(layer.outerARGB), Self.rgb(layer.peakARGB),
      Self.rgb(layer.hotCoreARGB), Self.rgb(layer.innerARGB),
      Self.rgb(layer.coreARGB),
    ]
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    metrics.withUnsafeBytes {
      encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1)
    }
    encoder.setFragmentBytes(&counts, length: MemoryLayout<SIMD2<Int32>>.stride, index: 2)
    colors.withUnsafeBytes {
      encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 3)
    }
    state.samples.withUnsafeBytes {
      encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 4)
    }
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("waveform_gpu_failed")
    }
    return texture
  }

  private static func rgb(_ argb: UInt32) -> SIMD3<Float> {
    SIMD3<Float>(
      Float((argb >> 16) & 0xff) / 255,
      Float((argb >> 8) & 0xff) / 255,
      Float(argb & 0xff) / 255
    )
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct WaveformOut { float4 position [[position]]; float2 uv; };
    vertex WaveformOut waveformVertex(uint vertexID [[vertex_id]]) {
      constexpr float2 positions[6] = {
        float2(-1,-1),float2(1,-1),float2(-1,1),
        float2(-1,1),float2(1,-1),float2(1,1)
      };
      constexpr float2 uvs[6] = {
        float2(0,1),float2(1,1),float2(0,0),
        float2(0,0),float2(1,1),float2(1,0)
      };
      WaveformOut out;
      out.position=float4(positions[vertexID],0,1);
      out.uv=uvs[vertexID];
      return out;
    }
    float waveformSample(constant float *samples,int index) {
      return samples[clamp(index,0,126)];
    }
    float waveformReducedSample(float x,constant float *samples,int sampleCount) {
      float maximum=float(max(sampleCount-1,1));
      float position=clamp(x,0.0,1.0)*maximum;
      float lower=floor(position); float upper=min(maximum,lower+1.0);
      int sourceLower=int(round(lower/maximum*126.0));
      int sourceUpper=int(round(upper/maximum*126.0));
      return mix(waveformSample(samples,sourceLower),waveformSample(samples,sourceUpper),
        fract(position));
    }
    // The authored Canvas path starts at sample 0, then uses sample i as
    // a quadratic control and midpoint(i,i+1) as its endpoint. Its monotonic
    // x coordinate has a closed-form inverse: no segment search is needed.
    // Returns amplitude and its derivative with respect to normalized x.
    float2 waveformCurve(float x,constant float *samples,int sampleCount) {
      int count=max(sampleCount,3);
      float maximum=float(count-1);
      float u=clamp(x,0.0,1.0)*maximum;
      if(u>=maximum-0.5) {
        float previous=waveformReducedSample((maximum-1)/maximum,samples,count);
        float last=waveformReducedSample(1.0,samples,count);
        float start=(previous+last)*0.5;
        return float2(mix(start,last,(u-maximum+0.5)*2.0),
          (last-start)*2.0*maximum);
      }
      int index=max(1,int(floor(u+0.5)));
      float previous=waveformReducedSample(float(index-1)/maximum,samples,count);
      float control=waveformReducedSample(float(index)/maximum,samples,count);
      float next=waveformReducedSample(float(index+1)/maximum,samples,count);
      float start=index==1 ? previous : (previous+control)*0.5;
      float end=(control+next)*0.5;
      float t=index==1 ? u/(1.0+sqrt(max(1.0-u*0.5,0.0))) : u-float(index)+0.5;
      float amplitude=mix(mix(start,control,t),mix(control,end,t),t);
      float derivative=2.0*mix(control-start,end-control,t);
      float dx=index==1 ? 2.0-t : 1.0;
      return float2(amplitude,derivative/dx*maximum);
    }
    float waveformStroke(float distancePixels,float widthPixels) {
      float halfWidth=max(widthPixels*0.5,0.35);
      return 1-smoothstep(halfWidth,halfWidth+1.0,distancePixels);
    }
    float waveformBloom(float distancePixels,float widthPixels,float blurPixels) {
      float halfWidth=max(widthPixels*0.5,0.35);
      float outside=max(distancePixels-halfWidth,0.0);
      float sigma=max(blurPixels,0.5);
      return exp(-0.5*outside*outside/(sigma*sigma));
    }
    void waveformAdd(thread float3 &premultiplied,thread float &alpha,
      float3 color,float coverage) {
      float sourceAlpha=clamp(coverage,0.0,1.0);
      premultiplied=clamp(premultiplied+color*sourceAlpha,0.0,1.0);
      alpha=clamp(alpha+sourceAlpha,0.0,1.0);
    }
    fragment half4 waveformFragment(
      WaveformOut in [[stage_in]],constant float2 &viewport [[buffer(0)]],
      constant float *metrics [[buffer(1)]],constant int2 &counts [[buffer(2)]],
      constant float3 *colors [[buffer(3)]],constant float *samples [[buffer(4)]]) {
      float opacity=metrics[0],energy=clamp(metrics[1],0.0,1.0);
      float peak=clamp(metrics[2],0.0,1.0),impact=clamp(metrics[3],0.0,1.0);
      float visibility=clamp(metrics[4]*opacity,0.0,1.0);
      float displacement=min(viewport.y*metrics[5],viewport.x*metrics[6]);
      float2 curve=waveformCurve(in.uv.x,samples,counts.x);
      float waveY=0.5-curve.x*displacement/max(viewport.y,1.0);
      float slope=-curve.y*displacement/max(viewport.x,1.0);
      // Local tangent distance is exact on straight/sloped sections. Curved
      // glow remains an approximation, not a full nearest-path/blur solve.
      float distancePixels=abs(in.uv.y-waveY)*viewport.y/sqrt(1.0+slope*slope);
      float pointScale=max(metrics[7],0.0001);
      float viewportScale=clamp(min(viewport.x,viewport.y)/pointScale/390.0,0.78,1.35)*pointScale;
      float3 premultiplied=float3(0); float alpha=0;
      if(counts.y>=4) {
        float a=min((0.14+peak*0.28+energy*0.18+impact*0.24)*visibility,0.78);
        waveformAdd(premultiplied,alpha,colors[0],waveformBloom(distancePixels,
          (11+peak*23+impact*18)*viewportScale,24*viewportScale)*a);
      }
      if(counts.y>=5&&peak>0.18) {
        float local=max(abs(waveformReducedSample(in.uv.x-1/max(viewport.x,1.0),samples,counts.x)),
          max(abs(waveformReducedSample(in.uv.x,samples,counts.x)),
          abs(waveformReducedSample(in.uv.x+1/max(viewport.x,1.0),samples,counts.x))));
        if(local>=max(0.12,peak*0.44)) {
          float a=min((0.10+peak*0.42+energy*0.10+impact*0.30)*visibility,0.82);
          waveformAdd(premultiplied,alpha,colors[1],waveformBloom(distancePixels,
            (5.5+peak*12+impact*9)*viewportScale,13*viewportScale)*a);
          a=min((0.12+peak*0.48+impact*0.24)*visibility,0.88);
          waveformAdd(premultiplied,alpha,colors[2],waveformBloom(distancePixels,
            (1.4+peak*2.2+impact*1.8)*viewportScale,3*viewportScale)*a);
        }
      }
      if(counts.y>=3) {
        float a=min((0.18+energy*0.28+impact*0.16)*visibility,0.62);
        waveformAdd(premultiplied,alpha,colors[0],waveformBloom(distancePixels,
          (5.8+energy*7.2+impact*4.8)*viewportScale,8*viewportScale)*a);
      }
      float a=min((0.70+energy*0.25)*visibility,0.96);
      waveformAdd(premultiplied,alpha,colors[3],waveformStroke(distancePixels,
        (2.1+energy*1.9+impact*1.4)*viewportScale)*a);
      a=min((0.92+energy*0.08)*visibility,1.0);
      waveformAdd(premultiplied,alpha,colors[4],waveformStroke(distancePixels,
        (1.15+energy*0.95+impact*0.75)*viewportScale)*a);
      if(alpha<=0.00001) discard_fragment();
      return half4(half3(clamp(premultiplied,0.0,alpha)),half(alpha));
    }
  """#
}

@available(iOS 15.0, *)
/// Replays the two-slot Radiant Emission pulse field at its authored 30 Hz.
/// Quality transitions reuse the state, so an impulse cannot restart or fire twice.
final class SceneRenderV2RadiantEmissionState {
  struct Pulse {
    var ageSeconds = 0.0
    var strength = 0.0
    var active = false

    var progress: Double {
      active ? min(1, ageSeconds / SceneRenderV2RadiantEmissionState.pulseDuration) : 1
    }

    mutating func advance() {
      guard active else { return }
      ageSeconds += SceneRenderV2RadiantEmissionState.sourceInterval
      if ageSeconds >= SceneRenderV2RadiantEmissionState.pulseDuration {
        ageSeconds = 0
        strength = 0
        active = false
      }
    }

    mutating func start(_ value: Double) {
      ageSeconds = 0
      strength = min(1, max(0, value))
      active = strength > 0
    }
  }

  let layerID: String
  private(set) var flow = 0.0
  private(set) var bass = 0.0
  private(set) var pulseA = Pulse()
  private(set) var pulseB = Pulse()
  private var flowTarget = 0.0
  private var bassTarget = 0.0
  private var playing = true
  private var nextStepHostTime: CFTimeInterval?
  private var signalSessionID: Int64 = -1
  private var lastImpactSerial: Int64 = 0
  private var lastAccentSerial: Int64 = 0
  private var lastBeatSerial: Int64 = 0
  private var lastFlashSerial: Int64 = 0

  init(layerID: String) { self.layerID = layerID }

  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    if frame.sessionId != signalSessionID {
      signalSessionID = frame.sessionId
      lastImpactSerial = 0
      lastAccentSerial = 0
      lastBeatSerial = 0
      lastFlashSerial = 0
    }
    let reactive = frame.available && frame.fresh && frame.musicActive
    let nextFlow = reactive ? unit(frame.channels[3]) : 0
    let nextBass = reactive ? unit(frame.channels[0]) : 0
    var impulse = 0.0
    if reactive {
      impulse = max(impulse, consume(frame.impact, last: &lastImpactSerial, emphasis: 1))
      impulse = max(impulse, consume(frame.flash, last: &lastFlashSerial, emphasis: 0.94))
      impulse = max(impulse, consume(frame.accent, last: &lastAccentSerial, emphasis: 0.82))
      impulse = max(impulse, consume(frame.beat, last: &lastBeatSerial, emphasis: 0.72))
    }
    let changed = nextFlow != flowTarget || nextBass != bassTarget || impulse > 0
    flowTarget = nextFlow
    bassTarget = nextBass
    if impulse > 0 { trigger(impulse) }
    return changed
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else { return false }
    guard let deadline = nextStepHostTime else {
      nextStepHostTime = hostTime + Self.sourceInterval
      return false
    }
    guard hostTime >= deadline else { return false }
    let due = min(
      Self.maximumHiddenSteps,
      Int(floor((hostTime - deadline) / Self.sourceInterval)) + 1
    )
    for _ in 0..<due { step() }
    let advanced = deadline + Double(due) * Self.sourceInterval
    nextStepHostTime = hostTime - advanced >= Self.sourceInterval
      ? hostTime + Self.sourceInterval
      : advanced
    return true
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard next != playing else { return }
    playing = next
    nextStepHostTime = next ? hostTime + Self.sourceInterval : nil
  }

  private func step() {
    flow = follow(flow, flowTarget)
    bass = follow(bass, bassTarget)
    pulseA.advance()
    pulseB.advance()
  }

  private func follow(_ current: Double, _ target: Double) -> Double {
    let rate = target >= current ? 10.0 : 4.2
    return current + (target - current) * (1 - Foundation.exp(-Self.sourceInterval * rate))
  }

  private func trigger(_ strength: Double) {
    if !pulseA.active {
      pulseA.start(strength)
    } else if !pulseB.active {
      pulseB.start(strength)
    } else if pulseA.progress >= pulseB.progress {
      pulseA.start(strength)
    } else {
      pulseB.start(strength)
    }
  }

  private func consume(
    _ event: SceneRenderSignalEventV2,
    last: inout Int64,
    emphasis: Double
  ) -> Double {
    guard event.active, event.serial > 0, event.serial != last else { return 0 }
    last = event.serial
    return unit(event.strength) * emphasis
  }

  private func unit(_ value: Float) -> Double { min(1, max(0, Double(value))) }

  static let sourceInterval = 1.0 / 30.0
  static let pulseDuration = 1.05
  private static let maximumHiddenSteps = 120
}

@available(iOS 15.0, *)
private final class SceneRenderV2RadialWarpMetalRenderer {
  private struct Particle {
    let angle: Float
    let baseSpeed: Float
    let initialProgress: Float
    let radiusFactor: Float
    let widthNoise: Float
    let paletteIndex: Float
    let cometEligible: Float
  }

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let particles: MTLBuffer

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("radial_warp_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard let vertex = library.makeFunction(name: "radialWarpVertex"),
          let fragment = library.makeFunction(name: "radialWarpFragment") else {
      throw RendererError("radial_warp_shader_missing")
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let values = (0..<460).map(Self.particle)
    guard let buffer = device.makeBuffer(
      bytes: values,
      length: MemoryLayout<Particle>.stride * values.count,
      options: .storageModeShared
    ) else { throw RendererError("radial_warp_particle_buffer_failed") }
    particles = buffer
  }

  func render(
    width: Int,
    height: Int,
    count: Int,
    bloom: Bool,
    opacity: Float,
    state: SceneRenderV2RadialWarpState,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard
      let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(
        device: device, width: width, height: height, allocator: outputAllocator
      ),
      let command = queue.makeCommandBuffer()
    else { throw RendererError("radial_warp_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("radial_warp_encoder_failed")
    }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(particles, offset: 0, index: 0)
    var size = SIMD2<Float>(Float(width), Float(height))
    var elapsed = Float(state.elapsedSeconds)
    var flow = Float(state.flowResponse)
    var bass = Float(state.bassResponse)
    var spark = Float(state.sparkResponse)
    var layerOpacity = opacity
    encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
    encoder.setVertexBytes(&elapsed, length: MemoryLayout<Float>.stride, index: 2)
    encoder.setVertexBytes(&flow, length: MemoryLayout<Float>.stride, index: 3)
    encoder.setVertexBytes(&bass, length: MemoryLayout<Float>.stride, index: 4)
    encoder.setVertexBytes(&spark, length: MemoryLayout<Float>.stride, index: 5)
    encoder.setVertexBytes(&layerOpacity, length: MemoryLayout<Float>.stride, index: 6)
    let passes: [Int32] = bloom ? [0, 1, 2] : [1, 2]
    for value in passes {
      var renderPass = value
      encoder.setVertexBytes(&renderPass, length: MemoryLayout<Int32>.stride, index: 7)
      encoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 6,
        instanceCount: count
      )
    }
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("radial_warp_gpu_failed")
    }
    return texture
  }

  private static func particle(_ index: Int) -> Particle {
    let widthNoise = noise(index, 4)
    let roll = Double((index * 97) % 100) / 100
    let palette: Float
    switch roll {
    case ..<0.30: palette = 2
    case ..<0.59: palette = 0
    case ..<0.84: palette = 1
    case ..<0.91: palette = 3
    case ..<0.96: palette = 4
    default: palette = 5
    }
    return Particle(
      angle: Float(Double(index) * 2.399963229728653 + (noise(index, 2) - 0.5) * 0.62),
      baseSpeed: Float(0.032 + noise(index, 6) * 0.026),
      initialProgress: Float(0.001 + noise(index, 1) * 0.998),
      radiusFactor: Float(0.72 + noise(index, 3) * 0.56),
      widthNoise: Float(widthNoise),
      paletteIndex: palette,
      cometEligible: index % 7 == 0 ? 1 : 0
    )
  }

  private static func noise(_ index: Int, _ salt: Int) -> Double {
    let value = Foundation.sin(Double(index) * 12.9898 + Double(salt) * 78.233) *
      43_758.5453
    return value - Foundation.floor(value)
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct Particle {
      float angle; float baseSpeed; float initialProgress; float radiusFactor;
      float widthNoise; float paletteIndex; float cometEligible;
    };
    struct VertexOut {
      float4 position [[position]];
      float2 uv;
      float isDot [[flat]];
      float3 color [[flat]];
      float opacity [[flat]];
    };
    float3 particlePalette(float index) {
      if (index < 0.5) return float3(48,216,255)/255.0;
      if (index < 1.5) return float3(43,92,255)/255.0;
      if (index < 2.5) return float3(244,251,255)/255.0;
      if (index < 3.5) return float3(255,179,58)/255.0;
      if (index < 4.5) return float3(139,234,85)/255.0;
      return float3(255,107,203)/255.0;
    }
    vertex VertexOut radialWarpVertex(
      uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
      device const Particle *particles [[buffer(0)]],
      constant float2 &size [[buffer(1)]], constant float &elapsed [[buffer(2)]],
      constant float &flow [[buffer(3)]], constant float &bass [[buffer(4)]],
      constant float &spark [[buffer(5)]], constant float &layerOpacity [[buffer(6)]],
      constant int &renderPass [[buffer(7)]]) {
      constexpr float2 vertices[6] = {
        float2(0,-1),float2(1,-1),float2(0,1),
        float2(0,1),float2(1,-1),float2(1,1)
      };
      Particle particle = particles[instanceID];
      float2 quadVertex = vertices[vertexID];
      float speedResponse = 1 + flow*0.28 + bass*0.20;
      float progress = fract(particle.initialProgress + elapsed*particle.baseSpeed*speedResponse);
      float2 direction = float2(cos(particle.angle),sin(particle.angle));
      // Match the authored ray-to-viewport edge, including its 8% overscan.
      float2 edgeByAxis = (size*0.5)/max(abs(direction),float2(0.0001));
      float edge = min(edgeByAxis.x,edgeByAxis.y)*1.08;
      float headDistance = edge*pow(progress,1.75);
      float baseTrail = 0.0015 + pow(progress,2.05)*(0.075+flow*0.010+bass*0.012);
      bool dot = progress < 0.28;
      bool comet = progress >= 0.84 && particle.cometEligible > 0.5;
      float trailScale = comet ? 3.0 : (progress >= 0.84 ? 1.35 : 1.0);
      float tailDistance = edge*pow(max(0.0,progress-baseTrail*trailScale),1.75);
      float fadeIn = clamp(progress/0.055,0.0,1.0);
      float fadeOut = clamp((1-progress)/0.045,0.0,1.0);
      float opacity = clamp((0.34+progress*0.64)*min(fadeIn,fadeOut)*(1+spark*0.18),0.0,1.0)*layerOpacity;
      float scale = clamp(min(size.x,size.y)/180.0,0.65,3.0);
      float2 normal = float2(-direction.y,direction.x);
      float2 center = size*0.5;
      float2 head = center+direction*headDistance;
      float2 tail = center+direction*tailDistance;
      float radius = (0.18+progress*0.84)*particle.radiusFactor*scale;
      float depth = smoothstep(0.0,1.0,(progress-0.28)/0.72);
      float nearEdge = smoothstep(0.0,1.0,(progress-0.84)/0.16);
      float width = comet
        ? (1.4+nearEdge*4.2)*(0.78+particle.widthNoise*0.40)*scale
        : (0.24+depth*0.88)*(0.75+particle.widthNoise*0.55)*scale;
      float baseWidth = width;
      float tailWidth = comet ? baseWidth*0.10 : max(baseWidth*0.08,0.06);
      float3 base = particlePalette(particle.paletteIndex);
      float highlight = dot ? 0.48 : (comet ? 0.72 : 0.58);
      VertexOut out;
      if (renderPass == 0) {
        float glowScale = dot ? 1.35 : (comet ? 1.35 : 1.18);
        radius=max(radius*glowScale,0.2);
        width=comet ? baseWidth*glowScale : max(baseWidth*glowScale,0.30);
        opacity*=dot ? 0.34 : (comet ? 0.52 : 0.30); out.color=base;
      } else if (renderPass == 2) {
        float start = comet ? 0.36 : (dot ? 0.0 : 0.24);
        tail=mix(tail,head,start);
        tailWidth=comet ? baseWidth*0.04 : max(baseWidth*0.025,0.03);
        width=comet ? baseWidth*0.32 : max(baseWidth*0.34,0.15);
        radius=max(radius,0.2);
        out.color=mix(base,float3(1),highlight);
      } else {
        width=comet ? baseWidth : max(baseWidth,0.30);
        opacity*=dot ? 0.0 : (comet ? 0.72 : 0.74); out.color=base;
      }
      float2 pixel;
      if (dot) pixel=head+float2((quadVertex.x-0.5)*2.0,quadVertex.y)*radius;
      else {
        float2 line=mix(tail,head,quadVertex.x);
        pixel=line+normal*quadVertex.y*mix(tailWidth,width,quadVertex.x)*0.5;
      }
      out.position=float4(pixel.x/size.x*2.0-1.0,1.0-pixel.y/size.y*2.0,0,1);
      out.uv=float2(quadVertex.x,quadVertex.y*0.5+0.5);
      out.isDot=dot ? 1.0 : 0.0; out.opacity=opacity;
      return out;
    }
    fragment half4 radialWarpFragment(VertexOut in [[stage_in]]) {
      float coverage=1.0;
      if (in.isDot>0.5) coverage=1.0-smoothstep(0.42,0.5,distance(in.uv,float2(0.5)));
      float alpha=clamp(in.opacity*coverage,0.0,1.0);
      return half4(half3(in.color*alpha),half(alpha));
    }
  """#
}

@available(iOS 15.0, *)
private final class SceneRenderV2SnowfallMetalRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private var particleBuffers = [Data: MTLBuffer]()

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("snowfall_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard let vertex = library.makeFunction(name: "snowfallVertex"),
          let fragment = library.makeFunction(name: "snowfallFragment") else {
      throw RendererError("snowfall_shader_missing")
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  func render(
    width: Int,
    height: Int,
    count: Int,
    pointScale: Float,
    opacity: Float,
    particleData: Data,
    state: SceneRenderV2SnowfallState,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    let particles: MTLBuffer
    if let cached = particleBuffers[particleData] {
      particles = cached
    } else {
      guard let created = particleData.withUnsafeBytes({
        (raw: UnsafeRawBufferPointer) -> MTLBuffer? in
        guard let base = raw.baseAddress else { return nil }
        return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
      }) else { throw RendererError("snowfall_particle_buffer_failed") }
      particleBuffers[particleData] = created
      particles = created
    }
    guard
      let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(
        device: device, width: width, height: height, allocator: outputAllocator
      ),
      let command = queue.makeCommandBuffer()
    else { throw RendererError("snowfall_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("snowfall_encoder_failed")
    }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(particles, offset: 0, index: 0)
    var elapsed = Float(state.elapsedSeconds)
    var scale = pointScale
    var layerOpacity = opacity
    encoder.setVertexBytes(&elapsed, length: MemoryLayout<Float>.stride, index: 1)
    encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.stride, index: 2)
    encoder.setVertexBytes(&layerOpacity, length: MemoryLayout<Float>.stride, index: 3)
    encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("snowfall_gpu_failed")
    }
    return texture
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct Particle {
      float x; float y; float speed; float drift; float driftSpeed;
      float phase; float travelTop; float travelSpan; uint band;
    };
    struct VertexOut {
      float4 position [[position]];
      float pointSize [[point_size]];
      half4 color [[flat]];
    };
    vertex VertexOut snowfallVertex(
      uint vertexID [[vertex_id]], device const Particle *particles [[buffer(0)]],
      constant float &elapsed [[buffer(1)]],
      constant float &pointScale [[buffer(2)]],
      constant float &layerOpacity [[buffer(3)]]) {
      Particle particle=particles[vertexID];
      float y=particle.travelTop+fmod(particle.y+elapsed*particle.speed,particle.travelSpan);
      float x=particle.x+sin(particle.phase+elapsed*particle.driftSpeed)*particle.drift;
      VertexOut out;
      out.position=float4(x*2.0-1.0,1.0-y*2.0,0,1);
      if (particle.band==0) {
        out.pointSize=0.65*pointScale;
        out.color=half4(half3(220,238,255)/255.0h,half(112.0/255.0));
      } else if (particle.band==1) {
        out.pointSize=1.15*pointScale;
        out.color=half4(half3(232,244,255)/255.0h,half(148.0/255.0));
      } else if (particle.band==2) {
        out.pointSize=1.85*pointScale;
        out.color=half4(half3(244,250,255)/255.0h,half(184.0/255.0));
      } else {
        out.pointSize=2.7*pointScale;
        out.color=half4(1,1,1,half(216.0/255.0));
      }
      out.color.a*=half(layerOpacity);
      return out;
    }
    fragment half4 snowfallFragment(
      VertexOut in [[stage_in]], float2 pointCoord [[point_coord]]) {
      float coverage=1.0-smoothstep(0.42,0.5,distance(pointCoord,float2(0.5)));
      half alpha=in.color.a*half(coverage);
      return half4(in.color.rgb*alpha,alpha);
    }
  """#
}

@available(iOS 15.0, *)
private final class SceneRenderV2PaintedStarlightMetalRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("painted_starlight_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard let vertex = library.makeFunction(name: "paintedStarlightVertex"),
          let fragment = library.makeFunction(name: "paintedStarlightFragment") else {
      throw RendererError("painted_starlight_shader_missing")
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
  }

  func render(
    width: Int,
    height: Int,
    opacity: Float,
    intensityScale: Double,
    state: SceneRenderV2PaintedStarlightState,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard
      let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(
        device: device, width: width, height: height, allocator: outputAllocator
      ),
      let command = queue.makeCommandBuffer()
    else { throw RendererError("painted_starlight_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("painted_starlight_encoder_failed")
    }
    encoder.setRenderPipelineState(pipeline)
    var viewport = SIMD2<Float>(Float(width), Float(height))
    var layerOpacity = opacity
    var bands = [Int32(
      min(15, max(0, Int((Double(state.moonBand) * intensityScale).rounded())))
    )]
    bands.append(contentsOf: state.starBands.map {
      Int32(min(15, max(0, Int((Double($0) * intensityScale).rounded()))))
    })
    encoder.setVertexBytes(
      &viewport,
      length: MemoryLayout<SIMD2<Float>>.stride,
      index: 0
    )
    bands.withUnsafeBytes { raw in
      if let base = raw.baseAddress {
        encoder.setVertexBytes(base, length: raw.count, index: 1)
      }
    }
    encoder.setFragmentBytes(
      &layerOpacity,
      length: MemoryLayout<Float>.stride,
      index: 0
    )
    encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("painted_starlight_gpu_failed")
    }
    return texture
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut {
      float4 position [[position]];
      float pointSize [[point_size]];
      int node [[flat]];
      float band [[flat]];
    };
    vertex VertexOut paintedStarlightVertex(
      uint vertexID [[vertex_id]],
      constant float2 &viewport [[buffer(0)]],
      constant int *bands [[buffer(1)]]) {
      constexpr float3 nodes[6] = {
        float3(0.807,0.144,0.245), float3(0.139,0.075,0.086),
        float3(0.635,0.343,0.073), float3(0.895,0.497,0.088),
        float3(0.171,0.798,0.076), float3(0.548,0.879,0.067)
      };
      float scale=max(viewport.x/936.0,viewport.y/1664.0);
      float2 renderSize=float2(936.0,1664.0)*scale;
      float2 origin=(viewport-renderSize)*0.5;
      float3 node=nodes[vertexID];
      float2 pixel=origin+node.xy*renderSize;
      VertexOut out;
      out.position=float4(
        pixel.x/viewport.x*2.0-1.0,
        1.0-pixel.y/viewport.y*2.0,
        0,1
      );
      out.pointSize=max(1.0,node.z*renderSize.x*2.0);
      out.node=int(vertexID);
      out.band=float(bands[vertexID]);
      return out;
    }
    float gradient4(float d,float4 stops,float4 values) {
      if (d<=stops.y) return mix(values.x,values.y,clamp((d-stops.x)/(stops.y-stops.x),0.0,1.0));
      if (d<=stops.z) return mix(values.y,values.z,clamp((d-stops.y)/(stops.z-stops.y),0.0,1.0));
      return mix(values.z,values.w,clamp((d-stops.z)/(stops.w-stops.z),0.0,1.0));
    }
    fragment half4 paintedStarlightFragment(
      VertexOut in [[stage_in]],
      float2 pointCoord [[point_coord]],
      constant float &opacity [[buffer(0)]]) {
      float d=length(pointCoord*2.0-1.0);
      if (d>=1.0) discard_fragment();
      bool moon=in.node==0;
      float react=pow(in.band/15.0,1.3);
      float3 color=moon ? float3(255,214,82)/255.0 : float3(255,231,128)/255.0;
      float halo=moon
        ? gradient4(d,float4(0,0.24,0.58,1),
            float4(0.10+react*0.24,0.05+react*0.16,0.008+react*0.07,0))
        : gradient4(d,float4(0,0.12,0.46,1),
            float4(0.18+react*0.55,0.06+react*0.28,0.005+react*0.10,0));
      float core=moon ? 0.0 :
        (1.0-smoothstep(0.045,0.055,d))*(0.10+react*0.86);
      float haloAlpha=clamp(halo*opacity,0.0,1.0);
      float coreAlpha=clamp(core*opacity,0.0,1.0);
      float3 premultiplied=color*haloAlpha+
        float3(1,1,217.0/255.0)*coreAlpha;
      float alpha=haloAlpha+coreAlpha;
      return half4(half3(premultiplied),half(alpha));
    }
  """#
}

@available(iOS 15.0, *)
private final class SceneRenderV2MagicStarsMetalRenderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let starsPipeline: MTLRenderPipelineState
  private let shootingPipeline: MTLRenderPipelineState
  private var buffers = [String: MTLBuffer]()

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw RendererError("magic_stars_command_queue_failed")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.metalSource, options: nil)
    guard
      let starsVertex = library.makeFunction(name: "magicStarsVertex"),
      let starsFragment = library.makeFunction(name: "magicStarsFragment"),
      let shootingVertex = library.makeFunction(name: "magicShootingStarVertex"),
      let shootingFragment = library.makeFunction(name: "magicShootingStarFragment")
    else { throw RendererError("magic_stars_shader_missing") }
    starsPipeline = try Self.pipeline(
      device: device,
      vertex: starsVertex,
      fragment: starsFragment
    )
    shootingPipeline = try Self.pipeline(
      device: device,
      vertex: shootingVertex,
      fragment: shootingFragment
    )
  }

  func render(
    width: Int,
    height: Int,
    opacity: Float,
    intensityScale: Float,
    pointScale: Float,
    state: SceneRenderV2MagicStarsState,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> MTLTexture {
    guard
      let texture = try SceneSurfaceNativeOutputAllocator.makeTexture(
        device: device, width: width, height: height, allocator: outputAllocator
      ),
      let command = queue.makeCommandBuffer(),
      let particleBuffer = particleBuffer(for: state)
    else { throw RendererError("magic_stars_target_failed") }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw RendererError("magic_stars_encoder_failed")
    }
    encoder.setRenderPipelineState(starsPipeline)
    encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
    var elapsed = Float(state.elapsedSeconds)
    var noise = Float(state.noiseLevel)
    var intensity = intensityScale
    var scale = pointScale * Float(state.controls.starSize)
    var color = state.controls.color
    var layerOpacity = opacity
    var authoredFrame = Int32(clamping: state.authoredFrame)
    var randomSeed = state.randomSeed
    encoder.setVertexBytes(&elapsed, length: MemoryLayout<Float>.stride, index: 1)
    encoder.setVertexBytes(&noise, length: MemoryLayout<Float>.stride, index: 2)
    encoder.setVertexBytes(&intensity, length: MemoryLayout<Float>.stride, index: 3)
    encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.stride, index: 4)
    encoder.setFragmentBytes(&noise, length: MemoryLayout<Float>.stride, index: 0)
    encoder.setFragmentBytes(&layerOpacity, length: MemoryLayout<Float>.stride, index: 1)
    encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD3<Float>>.stride, index: 4)
    encoder.setFragmentBytes(
      &authoredFrame,
      length: MemoryLayout<Int32>.stride,
      index: 2
    )
    encoder.setFragmentBytes(
      &randomSeed,
      length: MemoryLayout<UInt32>.stride,
      index: 3
    )
    encoder.drawPrimitives(
      type: .point,
      vertexStart: 0,
      vertexCount: state.attributes.count / SceneRenderV2MagicStarsState.attributeFloats
    )
    if state.shootingActive {
      scale = pointScale
      encoder.setRenderPipelineState(shootingPipeline)
      var viewport = SIMD2<Float>(Float(width), Float(height))
      var startX = Float(state.shootingStartX)
      var endX = Float(state.shootingEndX)
      var progress = Float(state.shootingProgress)
      var pointMode: Int32 = 0
      encoder.setVertexBytes(
        &viewport,
        length: MemoryLayout<SIMD2<Float>>.stride,
        index: 0
      )
      encoder.setVertexBytes(&startX, length: MemoryLayout<Float>.stride, index: 1)
      encoder.setVertexBytes(&endX, length: MemoryLayout<Float>.stride, index: 2)
      encoder.setVertexBytes(&progress, length: MemoryLayout<Float>.stride, index: 3)
      encoder.setVertexBytes(&pointMode, length: MemoryLayout<Int32>.stride, index: 4)
      encoder.setVertexBytes(&scale, length: MemoryLayout<Float>.stride, index: 5)
      encoder.setFragmentBytes(
        &layerOpacity,
        length: MemoryLayout<Float>.stride,
        index: 0
      )
      encoder.setFragmentBytes(
        &pointMode,
        length: MemoryLayout<Int32>.stride,
        index: 1
      )
      encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD3<Float>>.stride, index: 2)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
      pointMode = 1
      encoder.setVertexBytes(&pointMode, length: MemoryLayout<Int32>.stride, index: 4)
      encoder.setFragmentBytes(
        &pointMode,
        length: MemoryLayout<Int32>.stride,
        index: 1
      )
      encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 1)
    }
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
      throw command.error ?? RendererError("magic_stars_gpu_failed")
    }
    return texture
  }

  private func particleBuffer(for state: SceneRenderV2MagicStarsState) -> MTLBuffer? {
    let key = "\(state.layerID):\(state.attributesIdentity)"
    if let existing = buffers[key] { return existing }
    let buffer: MTLBuffer? = state.attributes.withUnsafeBytes { raw -> MTLBuffer? in
      guard let base = raw.baseAddress else { return nil }
      return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
    }
    if let buffer {
      // Keep only the currently rendered field, not every editor revision.
      buffers.removeAll(keepingCapacity: true)
      buffers[key] = buffer
    }
    return buffer
  }

  private static func pipeline(
    device: MTLDevice,
    vertex: MTLFunction,
    fragment: MTLFunction
  ) throws -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].rgbBlendOperation = .add
    descriptor.colorAttachments[0].alphaBlendOperation = .add
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    return try device.makeRenderPipelineState(descriptor: descriptor)
  }

  private struct RendererError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }

  static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct Star {
      float x; float y; float radius; float opacity; float phase;
      float flashing; float blinking; float dynamicStar; float itemIndex;
    };
    struct StarOut {
      float4 position [[position]];
      float pointSize [[point_size]];
      float baseRatio;
      float blinkRatio;
      float opacity;
      uint blinking [[flat]];
      uint dynamicStar [[flat]];
      uint itemIndex [[flat]];
    };
    vertex StarOut magicStarsVertex(
      uint vertexID [[vertex_id]],
      device const Star *stars [[buffer(0)]],
      constant float &elapsed [[buffer(1)]],
      constant float &noise [[buffer(2)]],
      constant float &intensityScale [[buffer(3)]],
      constant float &pointScale [[buffer(4)]]) {
      Star star=stars[vertexID];
      float cycle=fmod(elapsed,1.0);
      float ping=cycle<=0.5 ? cycle*2.0 : (1.0-cycle)*2.0;
      bool dynamicStar=star.dynamicStar>0.5;
      float radius=star.radius;
      if (dynamicStar && star.flashing>0.5) {
        radius*=(1.5+0.5*sin(ping*6.28318530718+star.phase))*noise;
      }
      float blinkRadius=radius;
      if (dynamicStar && star.blinking>0.5) {
        blinkRadius=radius*1.62*(0.8+0.2*sin(ping*6.28318530718));
      }
      float outerRadius=max(max(radius,blinkRadius),0.5);
      StarOut out;
      out.position=float4(star.x*2.0-1.0,1.0-star.y*2.0,0,1);
      out.pointSize=max(1.0,outerRadius*2.0*pointScale);
      out.baseRatio=max(radius,0.0)/outerRadius;
      out.blinkRatio=max(blinkRadius,0.0)/outerRadius;
      out.opacity=star.opacity*intensityScale;
      out.blinking=dynamicStar && star.blinking>0.5 ? 1u : 0u;
      out.dynamicStar=dynamicStar ? 1u : 0u;
      out.itemIndex=uint(max(star.itemIndex,0.0));
      return out;
    }
    uint magicMixedRandom(uint seed,uint itemIndex,uint frame) {
      uint value=seed^(itemIndex*0x9e3779b9u)^(frame*0x85ebca6bu);
      value^=value>>16; value*=0x7feb352du;
      value^=value>>15; value*=0x846ca68bu; value^=value>>16;
      return value;
    }
    fragment half4 magicStarsFragment(
      StarOut in [[stage_in]],
      float2 pointCoord [[point_coord]],
      constant float &noise [[buffer(0)]],
      constant float &layerOpacity [[buffer(1)]],
      constant int &authoredFrame [[buffer(2)]],
      constant uint &randomSeed [[buffer(3)]],
      constant float3 &color [[buffer(4)]]) {
      float distanceValue=length(pointCoord*2.0-1.0);
      float baseCoverage=1.0-smoothstep(
        max(in.baseRatio-0.10,0.0),max(in.baseRatio,0.0001),distanceValue);
      float baseAlpha=clamp(
        in.opacity*layerOpacity*baseCoverage,0.0,1.0);
      float3 premultiplied=color*baseAlpha;
      float alpha=baseAlpha;
      if (in.blinking==1u) {
        float blinkCoverage=1.0-smoothstep(
          max(in.blinkRatio-0.10,0.0),max(in.blinkRatio,0.0001),distanceValue);
        float blinkAlpha=clamp(
          (0.26+0.74*noise)*layerOpacity*blinkCoverage,0.0,1.0);
        premultiplied+=float3(blinkAlpha)*(1.0-alpha);
        alpha+=blinkAlpha*(1.0-alpha);
      }
      bool blurred=magicMixedRandom(
        in.dynamicStar==1u ? randomSeed : 0u,
        in.itemIndex,
        in.dynamicStar==1u ? uint(max(authoredFrame,0)) : 0u)%100u<1u;
      if (blurred) {
        float blur=exp(-distanceValue*distanceValue*7.5)*0.10*layerOpacity*(1.0-alpha);
        premultiplied+=color*blur; alpha+=blur;
      }
      if (alpha<=0.0001) discard_fragment();
      return half4(half3(premultiplied),half(alpha));
    }
    struct ShootingOut {
      float4 position [[position]];
      float pointSize [[point_size]];
      float alpha;
    };
    vertex ShootingOut magicShootingStarVertex(
      uint vertexID [[vertex_id]],
      constant float2 &viewport [[buffer(0)]],
      constant float &startX [[buffer(1)]],
      constant float &endX [[buffer(2)]],
      constant float &progress [[buffer(3)]],
      constant int &pointMode [[buffer(4)]],
      constant float &pointScale [[buffer(5)]]) {
      constexpr float2 vertices[6] = {
        float2(0,-0.5),float2(1,-0.5),float2(0,0.5),
        float2(0,0.5),float2(1,-0.5),float2(1,0.5)
      };
      float2 head=float2(mix(startX,endX,progress),progress)*viewport;
      float2 direction=normalize(float2(endX-startX,1.0));
      float2 tail=head-direction*50.0*pointScale;
      float2 quad=vertices[vertexID];
      float2 normal=float2(-direction.y,direction.x);
      float2 pixel=pointMode==1 ? head :
        mix(head,tail,quad.x)+normal*quad.y*pointScale;
      ShootingOut out;
      out.position=float4(
        pixel.x/viewport.x*2.0-1.0,1.0-pixel.y/viewport.y*2.0,0,1);
      out.pointSize=2.0*pointScale;
      out.alpha=pointMode==1
        ? (1.0-progress)
        : (1.0-quad.x)*0.8*(1.0-progress);
      return out;
    }
    fragment half4 magicShootingStarFragment(
      ShootingOut in [[stage_in]],
      float2 pointCoord [[point_coord]],
      constant float &opacity [[buffer(0)]],
      constant int &pointMode [[buffer(1)]],
      constant float3 &color [[buffer(2)]]) {
      if (pointMode==1 && length(pointCoord*2.0-1.0)>1.0) discard_fragment();
      float alpha=clamp(in.alpha*opacity,0.0,1.0);
      return half4(half3(color*alpha),half(alpha));
    }
  """#
}

struct SceneRenderV2RadialProfileLayer {
  let id: String
  let profileID: String
  let profileSource: CIImage
  let resourceIdentity: String
  let opacity: CGFloat
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
}

/// Host-time-locked replay of the installed chromatic profile. Presentation
/// cadence may skip profile frames at lower quality, but duration and event
/// identity never depend on the number of renders performed.
final class SceneRenderV2RadialProfileState {
  private(set) var layer: SceneRenderV2RadialProfileLayer
  private var signalSessionID: Int64 = -1
  private var eventSerials = Array(repeating: Int64(-1), count: 4)
  private var startedHostTime: CFTimeInterval?
  private var pausedHostTime: CFTimeInterval?
  private(set) var profileFrame = 0
  private(set) var major = false

  var active: Bool { startedHostTime != nil }

  init(layer: SceneRenderV2RadialProfileLayer) {
    self.layer = layer
  }

  func canReuse(for next: SceneRenderV2RadialProfileLayer) -> Bool {
    layer.id == next.id &&
      layer.profileID == next.profileID &&
      layer.resourceIdentity == next.resourceIdentity
  }

  func rebind(_ next: SceneRenderV2RadialProfileLayer) {
    precondition(canReuse(for: next))
    layer = next
  }

  func consume(_ frame: SceneRenderSignalFrameV2, hostTime: CFTimeInterval) -> Bool {
    if frame.sessionId != signalSessionID {
      signalSessionID = frame.sessionId
      eventSerials = Array(repeating: -1, count: eventSerials.count)
    }
    let events = [frame.impact, frame.accent, frame.beat, frame.flash]
    let reactive = frame.available && frame.fresh && frame.musicActive
    var selected: SceneRenderSignalEventV2?
    for index in events.indices {
      let event = events[index]
      guard event.serial > eventSerials[index] else { continue }
      eventSerials[index] = event.serial
      let authoredSource = frame.usesMappedMusicAuthority ? index < 3 : index == 3
      if reactive && authoredSource && event.serial > 0 && event.active &&
          (selected == nil || event.strength > selected!.strength) {
        selected = event
      }
    }
    guard let impulse = selected else { return false }
    startedHostTime = hostTime
    pausedHostTime = nil
    profileFrame = 0
    major = impulse.strength * 100 >= 82
    return true
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard let startedHostTime else { return false }
    let elapsed = max(0, hostTime - startedHostTime)
    let next = Int(floor(elapsed * 30))
    if next >= 112 {
      let changed = profileFrame != 0 || major
      self.startedHostTime = nil
      pausedHostTime = nil
      profileFrame = 0
      major = false
      return changed
    }
    guard next != profileFrame else { return false }
    profileFrame = next
    return true
  }

  func setPlaying(_ playing: Bool, hostTime: CFTimeInterval) {
    if playing {
      if let pausedHostTime, let startedHostTime {
        self.startedHostTime = startedHostTime + max(0, hostTime - pausedHostTime)
      }
      pausedHostTime = nil
    } else if startedHostTime != nil, pausedHostTime == nil {
      pausedHostTime = hostTime
    }
  }
}

@available(iOS 15.0, *)
private enum SceneRenderV2InstalledProgramKind: String {
  case blindingColors = "blinding_colors"
  case liquidLava = "liquid_lava"
  case enchantedFireflies = "enchanted_fireflies_v1"
  case infernoEmbers = "inferno_embers_v1"
  case wildflowerPollen = "wildflower_pollen_v1"
  case statefulStorm = "stateful_storm_energy_v1"
}

@available(iOS 15.0, *)
private struct SceneRenderV2InstalledProgramLayer {
  let id: String
  let configurationSignature: String
  let opacity: CGFloat
  let program: SceneRenderV2InstalledProgramKind
  let authoredSeed: UInt64
  let palette: [CIColor]
  let recipe: [String: Any]
  let renderScales: [String: Double]
  let framesPerSecondByQuality: [String: Int]
}

@available(iOS 15.0, *)
private final class SceneRenderV2InstalledProgramState {
  private enum Runtime {
    case blinding(sessionID: String, engine: MusicVibeRenderEngine)
    case liquidLava
    case fireflies(SceneSurfaceFirefliesRuntime)
    case inferno(SceneSurfaceInfernoEmbersRuntime)
    case pollen(SceneSurfaceWildflowerPollenRuntime)
    case storm(SceneSurfaceStatefulStormRuntime)
  }

  let layerID: String
  let program: SceneRenderV2InstalledProgramKind
  private let configurationSignature: String
  private let runtime: Runtime
  private var playing: Bool
  private var timelineTime: CFTimeInterval = 0
  private var lastAdvanceHostTime: CFTimeInterval?
  private var musicActive = false
  private var flow = 0.0
  private var bass = 0.0
  private var body = 0.0
  private var spark = 0.0
  private var latestAudioFrame: [String: Any]?
  private var tornDown = false

  init?(
    layer: SceneRenderV2InstalledProgramLayer,
    sceneSessionID: String,
    playing: Bool,
    renderEngine: MusicVibeRenderEngine?,
    metalContext: SceneSurfaceMetalContext?
  ) {
    layerID = layer.id
    program = layer.program
    configurationSignature = layer.configurationSignature
    self.playing = playing
    switch layer.program {
    case .blindingColors:
      guard let renderEngine else { return nil }
      let retainedID = "v2:\(sceneSessionID):\(layer.id):\(layer.configurationSignature.prefix(12))"
      guard renderEngine.retainForPictureInPicture(
        sessionId: retainedID,
        programId: SceneRenderV2InstalledProgramKind.blindingColors.rawValue,
        seed: layer.authoredSeed
      ) else { return nil }
      renderEngine.setRetainedProgramPlaying(
        sessionId: retainedID,
        playing: playing
      )
      runtime = .blinding(sessionID: retainedID, engine: renderEngine)
    case .liquidLava:
      runtime = .liquidLava
    case .enchantedFireflies:
      guard let recipe = SceneSurfaceFirefliesRecipeV1(layer.recipe) else {
        return nil
      }
      runtime = .fireflies(SceneSurfaceFirefliesRuntime(recipe: recipe))
    case .infernoEmbers:
      guard
        let recipe = SceneSurfaceInfernoEmbersRecipeV1(layer.recipe),
        let renderer = SceneSurfaceInfernoEmbersRuntime(
          recipe: recipe,
          metalContext: metalContext,
          metricsScope: "v2:\(sceneSessionID):\(layer.id)"
        )
      else { return nil }
      runtime = .inferno(renderer)
    case .wildflowerPollen:
      guard
        let recipe = SceneSurfaceWildflowerPollenRecipeV1(layer.recipe),
        let renderer = SceneSurfaceWildflowerPollenRuntime(
          recipe: recipe,
          metalContext: metalContext,
          metricsScope: "v2:\(sceneSessionID):\(layer.id)"
        )
      else { return nil }
      runtime = .pollen(renderer)
    case .statefulStorm:
      guard
        let recipe = SceneSurfaceStatefulStormRecipeV1(layer.recipe),
        let renderer = SceneSurfaceStatefulStormRuntime(
          recipe: recipe,
          palette: layer.palette
        )
      else { return nil }
      runtime = .storm(renderer)
    }
  }

  deinit { tearDown() }

  func canReuse(for layer: SceneRenderV2InstalledProgramLayer) -> Bool {
    layer.id == layerID && layer.program == program &&
      layer.configurationSignature == configurationSignature
  }

  func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
    guard playing != next else { return }
    playing = next
    lastAdvanceHostTime = hostTime
    if case .blinding(let sessionID, let engine) = runtime {
      engine.setRetainedProgramPlaying(sessionId: sessionID, playing: next)
    }
  }

  @discardableResult
  func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
    let reactive = frame.available && frame.fresh && frame.musicActive
    let nextFlow = reactive ? Self.unit(frame.channels[3]) : 0
    let nextBass = reactive ? Self.unit(frame.channels[0]) : 0
    let nextBody = reactive ? Self.unit(frame.channels[1]) : 0
    let nextSpark = reactive ? Self.unit(frame.channels[2]) : 0
    let changed = musicActive != reactive || flow != nextFlow || bass != nextBass ||
      body != nextBody || spark != nextSpark || frame.impact.active || frame.flash.active
    musicActive = reactive
    flow = nextFlow
    bass = nextBass
    body = nextBody
    spark = nextSpark
    latestAudioFrame = Self.legacyAudioFrame(frame, shouldReact: reactive)
    if playing, case .storm(let storm) = runtime, let latestAudioFrame {
      storm.updateAudioFrame(latestAudioFrame, hostTime: timelineTime)
    }
    return changed
  }

  func advance(hostTime: CFTimeInterval) -> Bool {
    guard playing else {
      lastAdvanceHostTime = hostTime
      return false
    }
    let delta = min(max(hostTime - (lastAdvanceHostTime ?? hostTime), 0), 0.1)
    lastAdvanceHostTime = hostTime
    timelineTime += delta
    return delta > 0
  }

  func image(
    layer: SceneRenderV2InstalledProgramLayer,
    targetRect: CGRect
  ) -> CIImage? {
    let raw: CIImage?
    switch runtime {
    case .blinding(let sessionID, let engine):
      raw = engine.renderRetainedProgramFrame(
        sessionId: sessionID,
        width: max(1, Int(targetRect.width.rounded())),
        height: max(1, Int(targetRect.height.rounded())),
        audioFrame: latestAudioFrame
      ).map { CIImage(cvPixelBuffer: $0) }
    case .liquidLava:
      raw = liquidLavaImage(layer: layer, targetRect: targetRect)
    case .fireflies(let renderer):
      raw = renderer.image(
        targetRect: targetRect,
        hostTime: timelineTime,
        musicActive: musicActive,
        flowDrive: flow,
        sparkDrive: spark,
        palette: layer.palette
      )
    case .inferno(let renderer):
      raw = renderer.image(
        targetRect: targetRect,
        hostTime: timelineTime,
        musicActive: musicActive,
        flowDrive: flow,
        bodyDrive: body,
        sparkDrive: spark,
        palette: layer.palette
      )
    case .pollen(let renderer):
      raw = renderer.image(
        targetRect: targetRect,
        hostTime: timelineTime,
        musicActive: musicActive,
        flowDrive: flow,
        sparkDrive: spark,
        palette: layer.palette
      )
    case .storm(let renderer):
      raw = renderer.image(targetRect: targetRect, hostTime: timelineTime)
    }
    guard var image = raw?.cropped(to: targetRect) else { return nil }
    if layer.opacity < 0.999_999 {
      image = image.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity),
        ]
      ).cropped(to: targetRect)
    }
    return image
  }

  func tearDown() {
    guard !tornDown else { return }
    tornDown = true
    if case .blinding(let sessionID, let engine) = runtime {
      engine.releasePictureInPicture(sessionId: sessionID)
    }
  }

  private func liquidLavaImage(
    layer: SceneRenderV2InstalledProgramLayer,
    targetRect: CGRect
  ) -> CIImage {
    var composed = CIImage(
      color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)
    ).cropped(to: targetRect)
    let colors = layer.palette.isEmpty ? [
      CIColor(red: 0.10, green: 0.86, blue: 0.92),
      CIColor(red: 0.94, green: 0.16, blue: 0.58),
      CIColor(red: 0.42, green: 0.31, blue: 1.00),
    ] : layer.palette
    for index in 0..<4 {
      let phase = timelineTime * (0.15 + Double(index) * 0.018) +
        Double(index) * 1.7
      let xWave = CGFloat((sin(phase * 0.73) + 1) * 0.5)
      let yWave = CGFloat((cos(phase) + 1) * 0.5)
      let radiusWave = CGFloat(sin(phase * 1.3))
      let radius = targetRect.width * (
        0.28 + 0.06 * radiusWave + CGFloat(bass) * 0.07
      )
      let color = colors[index % colors.count]
      guard let blob = CIFilter(
        name: "CIRadialGradient",
        parameters: [
          "inputCenter": CIVector(
            x: targetRect.width * (0.18 + 0.64 * xWave),
            y: targetRect.height * (0.12 + 0.76 * yWave)
          ),
          "inputRadius0": radius * 0.12,
          "inputRadius1": radius,
          "inputColor0": CIColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 0.38 + CGFloat(flow) * 0.12
          ),
          "inputColor1": CIColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 0
          ),
        ]
      )?.outputImage?.cropped(to: targetRect) else { continue }
      composed = blob.applyingFilter(
        "CIScreenBlendMode",
        parameters: [kCIInputBackgroundImageKey: composed]
      ).cropped(to: targetRect)
    }
    return composed
  }

  private static func legacyAudioFrame(
    _ frame: SceneRenderSignalFrameV2,
    shouldReact: Bool
  ) -> [String: Any] {
    [
      "audioSessionId": max(1, frame.sessionId),
      "sequence": frame.sequence,
      "shouldReact": shouldReact,
      "level": shouldReact ? unit(frame.dynamics[0]) : 0,
      "bassDrive": shouldReact ? unit(frame.channels[0]) : 0,
      "bodyDrive": shouldReact ? unit(frame.channels[1]) : 0,
      "sparkDrive": shouldReact ? unit(frame.channels[2]) : 0,
      "flowDrive": shouldReact ? unit(frame.channels[3]) : 0,
      "impactSerial": frame.impact.serial,
      "impactActive": shouldReact && frame.impact.active,
      "impactStrength": shouldReact ? unit(frame.impact.strength) : 0,
      "flashSerial": frame.flash.serial,
      "flashActive": shouldReact && frame.flash.active,
      "flashStrength": shouldReact ? unit(frame.flash.strength) : 0,
    ]
  }

  private static func unit(_ value: Float) -> Double {
    min(max(Double(value), 0), 1)
  }
}

struct SceneRenderV2DeadlineMetricsWindow: Equatable {
  let authoredDeadlines: Int
  let renderedFrames: Int
  let deadlineMisses: Int
}

struct SceneRenderV2PresentationInvalidation: OptionSet, Equatable {
  let rawValue: UInt8

  static let cadence = Self(rawValue: 1 << 0)
  static let signal = Self(rawValue: 1 << 1)
  static let flashHide = Self(rawValue: 1 << 2)
  static let recovery = Self(rawValue: 1 << 3)
}

struct SceneRenderV2PresentationToken: Equatable {
  let slot: UInt64
  let reasons: SceneRenderV2PresentationInvalidation
  fileprivate let cadenceGeneration: UInt64
  fileprivate let signalGeneration: UInt64
  fileprivate let flashHideGeneration: UInt64
  fileprivate let recoveryGeneration: UInt64
}

enum SceneRenderV2PresentationAction: Equatable {
  case idle
  case wait
  case submit(SceneRenderV2PresentationToken)
}

struct SceneRenderV2PresentationMetricsWindow: Equatable {
  let authoredDeadlines: Int
  let renderedFrames: Int
  let deadlineMisses: Int
  let maximumConsecutiveDeadlineMisses: Int
}

/// Serializes recurrent and recovery frame producers onto physical display slots.
///
/// Generations, instead of booleans, keep an invalidation that arrives while a
/// prior frame is being published. This makes cadence latest-wins without ever
/// consuming an ordered signal event before its complete frame is presented.
final class SceneRenderV2PresentationArbiter {
  private var cadenceGeneration: UInt64 = 0
  private var signalGeneration: UInt64 = 0
  private var flashHideGeneration: UInt64 = 0
  private var recoveryGeneration: UInt64 = 0
  private var completedCadenceGeneration: UInt64 = 0
  private var completedSignalGeneration: UInt64 = 0
  private var completedFlashHideGeneration: UInt64 = 0
  private var completedRecoveryGeneration: UInt64 = 0
  private var inFlightToken: SceneRenderV2PresentationToken?
  private var activeOpportunityToken: SceneRenderV2PresentationToken?
  private var authoredOpportunityActive = false
  private var authoredOpportunityMissed = false
  private var lastAttemptedSlot: UInt64?
  private var lastPublishedSlot: UInt64?
  private var windowAuthoredDeadlines = 0
  private var windowRenderedFrames = 0
  private var windowDeadlineMisses = 0
  private var consecutiveDeadlineMisses = 0
  private var maximumConsecutiveDeadlineMisses = 0

  var renderInFlight: Bool { inFlightToken != nil }
  var inFlightReasons: SceneRenderV2PresentationInvalidation {
    inFlightToken?.reasons ?? []
  }
  var hasActiveAuthoredOpportunity: Bool { authoredOpportunityActive }

  var pendingReasons: SceneRenderV2PresentationInvalidation {
    var reasons: SceneRenderV2PresentationInvalidation = []
    if cadenceGeneration > completedCadenceGeneration { reasons.insert(.cadence) }
    if signalGeneration > completedSignalGeneration { reasons.insert(.signal) }
    if flashHideGeneration > completedFlashHideGeneration {
      reasons.insert(.flashHide)
    }
    if recoveryGeneration > completedRecoveryGeneration {
      reasons.insert(.recovery)
    }
    return reasons
  }

  func invalidate(_ reasons: SceneRenderV2PresentationInvalidation) {
    if reasons.contains(.cadence) { invalidateCadenceOpportunity() }
    if reasons.contains(.signal) { signalGeneration &+= 1 }
    if reasons.contains(.flashHide) { flashHideGeneration &+= 1 }
    if reasons.contains(.recovery) { recoveryGeneration &+= 1 }
  }

  func beginPresentation(slot: UInt64) -> SceneRenderV2PresentationAction {
    let reasons = pendingReasons
    guard !reasons.isEmpty else { return .idle }
    guard inFlightToken == nil,
          lastAttemptedSlot != slot,
          lastPublishedSlot != slot else { return .wait }
    lastAttemptedSlot = slot
    if !authoredOpportunityActive {
      authoredOpportunityActive = true
      authoredOpportunityMissed = false
    }
    let token = SceneRenderV2PresentationToken(
      slot: slot,
      reasons: reasons,
      cadenceGeneration: cadenceGeneration,
      signalGeneration: signalGeneration,
      flashHideGeneration: flashHideGeneration,
      recoveryGeneration: recoveryGeneration
    )
    if activeOpportunityToken == nil {
      activeOpportunityToken = token
    }
    inFlightToken = token
    return .submit(token)
  }

  func completePresentation(
    _ token: SceneRenderV2PresentationToken,
    publishedSlot: UInt64? = nil,
    fulfilledReasons: SceneRenderV2PresentationInvalidation? = nil
  ) {
    guard inFlightToken == token else { return }
    completeCapturedGenerations(
      token,
      reasons: (fulfilledReasons ?? token.reasons).intersection(token.reasons)
    )
    inFlightToken = nil
    lastPublishedSlot = publishedSlot ?? token.slot
    settleCurrentOpportunity(rendered: true)
  }

  func retryPresentation(_ token: SceneRenderV2PresentationToken) {
    guard inFlightToken == token else { return }
    inFlightToken = nil
    recordCurrentOpportunityMiss()
  }

  func failPresentation(
    _ token: SceneRenderV2PresentationToken,
    failedReasons: SceneRenderV2PresentationInvalidation? = nil
  ) {
    guard inFlightToken == token else { return }
    completeCapturedGenerations(
      token,
      reasons: (failedReasons ?? token.reasons).intersection(token.reasons)
    )
    inFlightToken = nil
    recordCurrentOpportunityMiss()
    settleCurrentOpportunity(rendered: false)
  }

  /// Records one missed authored deadline without turning every intervening
  /// display refresh into another authored opportunity. The pending generation
  /// remains authoritative and may still publish on a later physical slot.
  func recordCurrentOpportunityMiss() {
    guard authoredOpportunityActive, !authoredOpportunityMissed else { return }
    authoredOpportunityMissed = true
  }

  func discard(_ reasons: SceneRenderV2PresentationInvalidation) {
    if reasons.contains(.cadence) {
      completedCadenceGeneration = cadenceGeneration
    }
    if reasons.contains(.signal) {
      completedSignalGeneration = signalGeneration
    }
    if reasons.contains(.flashHide) {
      completedFlashHideGeneration = flashHideGeneration
    }
    if reasons.contains(.recovery) {
      completedRecoveryGeneration = recoveryGeneration
    }
    if inFlightToken == nil, pendingReasons.isEmpty {
      if authoredOpportunityActive {
        recordCurrentOpportunityMiss()
        settleCurrentOpportunity(rendered: false)
      }
    }
  }

  /// Cancels work that stopped being eligible because playback was suspended.
  /// Unlike a failed presentation, this does not turn an app lifecycle change
  /// into a renderer deadline miss.
  func discardForPlaybackSuspension(
    _ reasons: SceneRenderV2PresentationInvalidation
  ) {
    if reasons.contains(.cadence) {
      completedCadenceGeneration = cadenceGeneration
    }
    if reasons.contains(.signal) {
      completedSignalGeneration = signalGeneration
    }
    if reasons.contains(.flashHide) {
      completedFlashHideGeneration = flashHideGeneration
    }
    if reasons.contains(.recovery) {
      completedRecoveryGeneration = recoveryGeneration
    }
    if inFlightToken == nil, pendingReasons.isEmpty {
      authoredOpportunityActive = false
      authoredOpportunityMissed = false
      activeOpportunityToken = nil
    }
  }

  func recordSkippedOpportunities(_ count: Int) {
    guard count > 0 else { return }
    windowAuthoredDeadlines += count
    windowDeadlineMisses += count
    consecutiveDeadlineMisses += count
    maximumConsecutiveDeadlineMisses = max(
      maximumConsecutiveDeadlineMisses,
      consecutiveDeadlineMisses
    )
  }

  func drainMetrics() -> SceneRenderV2PresentationMetricsWindow {
    let result = SceneRenderV2PresentationMetricsWindow(
      authoredDeadlines: windowAuthoredDeadlines,
      renderedFrames: windowRenderedFrames,
      deadlineMisses: windowDeadlineMisses,
      maximumConsecutiveDeadlineMisses: maximumConsecutiveDeadlineMisses
    )
    windowAuthoredDeadlines = 0
    windowRenderedFrames = 0
    windowDeadlineMisses = 0
    consecutiveDeadlineMisses = 0
    maximumConsecutiveDeadlineMisses = 0
    return result
  }

  func resetMetrics() {
    windowAuthoredDeadlines = 0
    windowRenderedFrames = 0
    windowDeadlineMisses = 0
    consecutiveDeadlineMisses = 0
    maximumConsecutiveDeadlineMisses = 0
  }

  func reset() {
    cadenceGeneration = 0
    signalGeneration = 0
    flashHideGeneration = 0
    recoveryGeneration = 0
    completedCadenceGeneration = 0
    completedSignalGeneration = 0
    completedFlashHideGeneration = 0
    completedRecoveryGeneration = 0
    inFlightToken = nil
    activeOpportunityToken = nil
    authoredOpportunityActive = false
    authoredOpportunityMissed = false
    lastAttemptedSlot = nil
    lastPublishedSlot = nil
    resetMetrics()
  }

  private func completeCapturedGenerations(
    _ token: SceneRenderV2PresentationToken,
    reasons: SceneRenderV2PresentationInvalidation? = nil
  ) {
    let reasons = reasons ?? token.reasons
    if reasons.contains(.cadence) {
      completedCadenceGeneration = max(
        completedCadenceGeneration,
        token.cadenceGeneration
      )
    }
    if reasons.contains(.signal) {
      completedSignalGeneration = max(
        completedSignalGeneration,
        token.signalGeneration
      )
    }
    if reasons.contains(.flashHide) {
      completedFlashHideGeneration = max(
        completedFlashHideGeneration,
        token.flashHideGeneration
      )
    }
    if reasons.contains(.recovery) {
      completedRecoveryGeneration = max(
        completedRecoveryGeneration,
        token.recoveryGeneration
      )
    }
  }

  /// Advances one logical cadence deadline. A newer cadence state may wait for
  /// the next physical refresh, but it never disappears into an older retry.
  /// If an unattempted cadence generation is superseded, that generation is a
  /// real authored miss; faster display refreshes alone never call this path.
  private func invalidateCadenceOpportunity() {
    let activeCadenceGeneration = activeOpportunityToken?.cadenceGeneration ??
      completedCadenceGeneration
    if cadenceGeneration > max(
      completedCadenceGeneration,
      activeCadenceGeneration
    ) {
      recordSettledMissedOpportunity()
    } else if authoredOpportunityActive {
      recordCurrentOpportunityMiss()
      if inFlightToken == nil {
        if let activeOpportunityToken,
           activeOpportunityToken.reasons.contains(.cadence) {
          completedCadenceGeneration = max(
            completedCadenceGeneration,
            activeOpportunityToken.cadenceGeneration
          )
        }
        settleCurrentOpportunity(rendered: false)
      }
    }
    cadenceGeneration &+= 1
  }

  private func settleCurrentOpportunity(rendered: Bool) {
    guard authoredOpportunityActive else { return }
    windowAuthoredDeadlines += 1
    if authoredOpportunityMissed {
      recordMissedDeadline()
    }
    if rendered {
      windowRenderedFrames += 1
      consecutiveDeadlineMisses = 0
    }
    authoredOpportunityActive = false
    authoredOpportunityMissed = false
    activeOpportunityToken = nil
  }

  private func recordSettledMissedOpportunity() {
    windowAuthoredDeadlines += 1
    recordMissedDeadline()
  }

  private func recordMissedDeadline() {
    windowDeadlineMisses += 1
    consecutiveDeadlineMisses += 1
    maximumConsecutiveDeadlineMisses = max(
      maximumConsecutiveDeadlineMisses,
      consecutiveDeadlineMisses
    )
  }
}

struct SceneRenderV2MetalCapabilityDescriptor: Equatable {
  let deviceName: String
  let maxThreadsWidth: Int
  let maxThreadsHeight: Int
  let maxThreadsDepth: Int
  let maxThreadgroupMemoryLength: Int
  let maxBufferLength: UInt64
  let readWriteTextureTier: Int
  let argumentBuffersTier: Int

  fileprivate var canonicalValue: String {
    [
      Self.normalize(deviceName),
      String(maxThreadsWidth),
      String(maxThreadsHeight),
      String(maxThreadsDepth),
      String(maxThreadgroupMemoryLength),
      String(maxBufferLength),
      String(readWriteTextureTier),
      String(argumentBuffersTier),
    ].joined(separator: "|")
  }

  private static func normalize(_ value: String) -> String {
    let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "_"
    }
    return String(scalars)
      .split(separator: "_", omittingEmptySubsequences: true)
      .joined(separator: "_")
  }
}

func sceneRenderV2MetalCapabilityClass(
  _ descriptor: SceneRenderV2MetalCapabilityDescriptor
) -> String {
  let digest = SHA256.hash(data: Data(descriptor.canonicalValue.utf8)).prefix(6)
    .map { String(format: "%02x", $0) }
    .joined()
  return "ios_metal_v2_c1_\(digest)"
}

func sceneRenderV2DeadlineMetricsWindow(
  scheduledDeadlines: Int,
  noChangeTicks: Int,
  completedFrames: Int,
  backpressureEvents: Int
) -> SceneRenderV2DeadlineMetricsWindow {
  let completed = max(0, completedFrames)
  let cadenceDeadlines = max(
    0,
    max(0, scheduledDeadlines) - max(0, noChangeTicks)
  )
  let authored = max(
    cadenceDeadlines,
    completed + max(0, backpressureEvents)
  )
  return SceneRenderV2DeadlineMetricsWindow(
    authoredDeadlines: authored,
    renderedFrames: min(authored, completed),
    deadlineMisses: max(0, authored - completed)
  )
}

func sceneRenderV2PresentationFramesPerSecond(
  logicalFramesPerSecond: Int,
  maximumPresentationFramesPerSecond: Int
) -> Int {
  min(
    max(1, logicalFramesPerSecond),
    max(1, maximumPresentationFramesPerSecond)
  )
}

struct SceneRenderV2PlaybackGate {
  static func effectivePlayback(
    requestedForegroundPlaying: Bool,
    applicationActive: Bool,
    pictureInPictureRetained: Bool,
    pictureInPicturePlaying: Bool
  ) -> Bool {
    (requestedForegroundPlaying && applicationActive) ||
      (pictureInPictureRetained && pictureInPicturePlaying)
  }

  static func transition(
    from currentPlaying: Bool,
    requestedForegroundPlaying: Bool,
    applicationActive: Bool,
    pictureInPictureRetained: Bool,
    pictureInPicturePlaying: Bool
  ) -> Bool? {
    let next = effectivePlayback(
      requestedForegroundPlaying: requestedForegroundPlaying,
      applicationActive: applicationActive,
      pictureInPictureRetained: pictureInPictureRetained,
      pictureInPicturePlaying: pictureInPicturePlaying
    )
    return next == currentPlaying ? nil : next
  }
}

func sceneRenderV2ShouldSchedulePresentationTimer(
  playing: Bool,
  hasCadenceDeadline: Bool,
  hasPendingInvalidation: Bool,
  renderInFlight: Bool
) -> Bool {
  playing && (
    hasCadenceDeadline || hasPendingInvalidation || renderInFlight
  )
}

func sceneRenderV2LoopPhaseMicros(
  mediaPtsMicros: Int64,
  durationMicros: Int64?
) -> Int64 {
  let nonnegativePts = max(0, mediaPtsMicros)
  guard let durationMicros, durationMicros > 0 else {
    return nonnegativePts
  }
  return nonnegativePts % durationMicros
}

final class SceneRenderV2ApplicationActivitySignal: @unchecked Sendable {
  private let lock = NSLock()
  private var storedActive: Bool

  init(active: Bool) { storedActive = active }

  var active: Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedActive
  }

  @discardableResult
  func setActive(_ active: Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard storedActive != active else { return false }
    storedActive = active
    return true
  }
}

/// Invalidates resource preparation from the calling thread while the runtime
/// queue is servicing a bounded AVFoundation seek/preroll wait. This avoids a
/// detach, replacement request, or shutdown waiting behind work that it has
/// already made obsolete.
final class SceneRenderV2PreparationGeneration: @unchecked Sendable {
  private let lock = NSLock()
  private var storedGeneration: UInt64 = 0

  @discardableResult
  func begin() -> UInt64 {
    lock.lock()
    storedGeneration &+= 1
    let generation = storedGeneration
    lock.unlock()
    return generation
  }

  func invalidate() {
    lock.lock()
    storedGeneration &+= 1
    lock.unlock()
  }

  func isCurrent(_ generation: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedGeneration == generation
  }

  /// Linearizes a short publication against begin/invalidate. The body must
  /// not call user code or re-enter this generation object.
  func commitIfCurrent(
    _ generation: UInt64,
    publication: () -> Bool
  ) -> Bool {
    lock.lock()
    guard storedGeneration == generation else {
      lock.unlock()
      return false
    }
    let committed = publication()
    lock.unlock()
    return committed
  }
}

enum SceneRenderV2MediaCommitPhase: Equatable {
  case preparing
  case rendered
  case published
  case invalidated
}

/// Playback authority for a candidate media graph. Decoders may produce one
/// paused preroll frame, but continuous playback starts only after that exact
/// graph buffer has been published.
final class SceneRenderV2MediaCommitGate {
  private let lock = NSLock()
  private var storedPhase: SceneRenderV2MediaCommitPhase = .preparing

  var phase: SceneRenderV2MediaCommitPhase {
    lock.lock()
    defer { lock.unlock() }
    return storedPhase
  }

  @discardableResult
  func markRendered() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard storedPhase == .preparing else { return false }
    storedPhase = .rendered
    return true
  }

  @discardableResult
  func markPublished() -> Bool {
    commitPublication {}
  }

  /// Executes the physical texture publication and changes playback authority
  /// in one ordering point. An invalidated transaction cannot run the body.
  @discardableResult
  func commitPublication(_ publication: () -> Void) -> Bool {
    lock.lock()
    guard storedPhase == .rendered else {
      lock.unlock()
      return false
    }
    publication()
    storedPhase = .published
    lock.unlock()
    return true
  }

  func invalidate() {
    lock.lock()
    storedPhase = .invalidated
    lock.unlock()
  }

  func shouldPlay(effectivePlaying: Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedPhase == .published && effectivePlaying
  }
}

func sceneRenderV2DecoderTransitionWithinBudget(
  liveDecoderCount: Int,
  newDecoderCount: Int,
  maximumDecoderCount: Int = 2
) -> Bool {
  liveDecoderCount >= 0 &&
    newDecoderCount >= 0 &&
    maximumDecoderCount >= 0 &&
    liveDecoderCount + newDecoderCount <= maximumDecoderCount
}

func sceneRenderV2ShouldRestartMediaLoop(
  playing: Bool,
  playerIsCurrent: Bool,
  invalidated: Bool
) -> Bool {
  playing && playerIsCurrent && !invalidated
}

enum SceneRenderV2PrerollReadiness: Equatable {
  case waiting
  case ready
  case failed
}

func sceneRenderV2PrerollReadiness(
  playerStatus: AVPlayer.Status,
  itemStatus: AVPlayerItem.Status
) -> SceneRenderV2PrerollReadiness {
  if playerStatus == .failed || itemStatus == .failed { return .failed }
  if playerStatus == .readyToPlay && itemStatus == .readyToPlay {
    return .ready
  }
  return .waiting
}

func sceneRenderV2CanInvokePreroll(
  preparationCurrent: Bool,
  playerIsCurrent: Bool,
  itemIsCurrent: Bool,
  playerRate: Float,
  playerStatus: AVPlayer.Status,
  itemStatus: AVPlayerItem.Status
) -> Bool {
  preparationCurrent &&
    playerIsCurrent &&
    itemIsCurrent &&
    playerRate == 0 &&
    sceneRenderV2PrerollReadiness(
      playerStatus: playerStatus,
      itemStatus: itemStatus
    ) == .ready
}

final class SceneRenderV2PrerollCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private var storedOutcome: Bool?

  var outcome: Bool? {
    lock.lock()
    defer { lock.unlock() }
    return storedOutcome
  }

  @discardableResult
  func complete(_ outcome: Bool) -> Bool {
    lock.lock()
    guard storedOutcome == nil else {
      lock.unlock()
      return false
    }
    storedOutcome = outcome
    lock.unlock()
    semaphore.signal()
    return true
  }

  func wait(
    until deadline: DispatchTime,
    onWait: () -> Void,
    shouldContinue: () -> Bool = { true }
  ) -> Bool {
    while true {
      if let outcome { return outcome }
      guard shouldContinue() else {
        cancel()
        return false
      }
      let now = DispatchTime.now()
      guard now < deadline else {
        return complete(false) ? false : (outcome ?? false)
      }
      onWait()
      let sliceNanos = min(
        deadline.uptimeNanoseconds,
        now.uptimeNanoseconds &+ 5_000_000
      )
      if semaphore.wait(
        timeout: DispatchTime(uptimeNanoseconds: sliceNanos)
      ) == .success {
        return outcome ?? false
      }
    }
  }

  func cancel() { _ = complete(false) }
}

final class SceneRenderV2ImageSurfaceRuntime {
  typealias GraphicsResourceFactory = () -> (MTLDevice, CIContext)?

  /// A component source, not a V2 scene: V1 owns its clock, composition,
  /// publication and audio delivery. Only the installed component math is shared.
  final class NativeProgram {
    private typealias Library = SceneRenderV2ImageSurfaceRuntime
    private var node: GraphNode?
    private var originalParameters: [String: Any]
    private let catalogProgram: SceneCatalogNativeProgram?
    private let graphics: GraphicsResources?
    private let outputAllocator: SceneSurfaceNativeOutputAllocator?
    private let logicalSize: CGSize
    private var playing = true
    private var lastHostTime: CFTimeInterval?
    private var signalSessionID: Int64?
    private var signalSequence: Int64 = -1
    private var flashAwaitingPublication = false
    private var flashHideAt: CFTimeInterval?
    private var flashCleanupAwaitingPublication = false
    private var strobe: StrobeState?
    private var radialProfile: SceneRenderV2RadialProfileState?
    private var radialWarp: SceneRenderV2RadialWarpState?
    private var snowfall: SceneRenderV2SnowfallState?
    private var paintedStarlight: SceneRenderV2PaintedStarlightState?
    private var magicStars: SceneRenderV2MagicStarsState?
    private var magicMoon: SceneRenderV2MagicMoonState?
    private var radiantEmission: SceneRenderV2RadiantEmissionState?
    private var rainbowWaterfall: SceneRenderV2RainbowWaterfallState?
    private var neonPulse: SceneRenderV2NeonPulseState?
    private var embeddedScreen: SceneRenderV2EmbeddedScreenState?
    private var waveform: SceneRenderV2WaveformState?

    static func validate(parameters: [String: Any]) -> Bool {
      SceneCatalogNativeDescriptor.parse(parameters) != nil ||
        parse(parameters: parameters, loadImage: false) != nil
    }

    private static func parse(
      parameters: [String: Any], loadImage: Bool
    ) -> GraphNode? {
      guard Set(parameters.keys) == Set([
              "document", "resolvedResourcePaths", "logicalWidth", "logicalHeight",
            ]),
            let logicalWidth = Library.finitePositive(parameters["logicalWidth"]),
            let logicalHeight = Library.finitePositive(parameters["logicalHeight"]),
            logicalWidth <= 8192, logicalHeight <= 8192,
            let document = parameters["document"] as? [String: Any],
            Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
            let layers = document["layers"] as? [[String: Any]],
            layers.count == 1, let layer = layers.first,
            Library.identityTransform(layer["transform"]),
            Library.number(layer["opacity"], equals: 1),
            let paths = Library.stringMap(parameters["resolvedResourcePaths"]),
            let materialized = Library.materializeResources(document, resolvedPaths: paths),
            let parsed = Library.parseDocument(materialized, loadImage: loadImage),
            parsed.filter == nil, let node = parsed.nodes.first,
            parsed.nodes.count == 1 else { return nil }
      switch node {
      case .image, .media, .installedProgram:
        // V1 already owns these sources and retained program sessions. Do not
        // introduce a second media/program owner through this adapter.
        return nil
      default: return node
      }
    }

    init?(
      parameters: [String: Any],
      renderEngine: MusicVibeRenderEngine,
      metalContext: SceneSurfaceMetalContext?
    ) {
      originalParameters = parameters
      if let descriptor = SceneCatalogNativeDescriptor.parse(parameters) {
        guard let metalContext,
          let program = SceneCatalogNativeProgram(descriptor: descriptor, device: metalContext.device)
        else { return nil }
        node = nil
        catalogProgram = program
        graphics = nil
        outputAllocator = nil
        logicalSize = descriptor.logicalSize
        setPlaying(false, hostTime: CACurrentMediaTime())
        return
      }
      guard let node = Self.parse(parameters: parameters, loadImage: true) else {
        return nil
      }
      self.node = node
      catalogProgram = nil
      logicalSize = CGSize(
        width: Library.finitePositive(parameters["logicalWidth"])!,
        height: Library.finitePositive(parameters["logicalHeight"])!
      )
      graphics = metalContext.map {
        GraphicsResources(device: $0.device, ciContext: $0.ciContext)
      }
      switch node {
      case .radialWarp, .snowfall, .paintedStarlight, .magicStars,
           .neonPulse, .embeddedScreen, .waveform:
        outputAllocator = metalContext.map { SceneSurfaceNativeOutputAllocator(device: $0.device) }
      default:
        outputAllocator = nil
      }
      // Seeded sources keep one stable component seed; this does not introduce
      // a scene clock or change their state when another component is added.
      let seed: UInt32 = 1
      switch node {
      case .solidColor, .blueSky: break
      case .strobe(let layer, _):
        strobe = StrobeState(layer: layer, playing: false)
      case .radialProfile(let layer):
        radialProfile = SceneRenderV2RadialProfileState(layer: layer)
      case .radialWarp(let layer):
        guard graphics?.radialWarpRenderer != nil else { return nil }
        radialWarp = SceneRenderV2RadialWarpState(layerID: layer.id)
      case .snowfall(let layer):
        guard graphics?.snowfallRenderer != nil else { return nil }
        snowfall = SceneRenderV2SnowfallState(layerID: layer.id)
      case .paintedStarlight(let layer):
        guard graphics?.paintedStarlightRenderer != nil else { return nil }
        paintedStarlight = SceneRenderV2PaintedStarlightState(layerID: layer.id)
      case .magicStars(let layer):
        guard graphics?.magicStarsRenderer != nil else { return nil }
        magicStars = SceneRenderV2MagicStarsState(layerID: layer.id, sessionSeed: seed)
        magicStars?.applyControls(layer.controls)
      case .magicMoon(let layer):
        magicMoon = SceneRenderV2MagicMoonState(layerID: layer.id)
      case .radiantEmission(let layer):
        radiantEmission = SceneRenderV2RadiantEmissionState(layerID: layer.id)
      case .rainbowWaterfall(let layer):
        rainbowWaterfall = SceneRenderV2RainbowWaterfallState(layerID: layer.id)
      case .neonPulse(let layer):
        guard graphics?.neonPulseRenderer != nil else { return nil }
        neonPulse = SceneRenderV2NeonPulseState(layerID: layer.id, sessionSeed: seed)
        neonPulse?.controls = layer.controls
      case .embeddedScreen(let layer):
        guard graphics?.embeddedScreenRenderer != nil else { return nil }
        embeddedScreen = SceneRenderV2EmbeddedScreenState(layerID: layer.id)
      case .waveform(let layer):
        guard graphics?.waveformRenderer != nil else { return nil }
        waveform = SceneRenderV2WaveformState(layerID: layer.id)
      case .image, .media, .installedProgram: return nil
      }
      setPlaying(false, hostTime: CACurrentMediaTime())
      _ = renderEngine // Signature shared with other V1 installed sources.
    }

    func prepareCatalogControlUpdate(parameters: [String: Any]) -> SceneCatalogControlUpdate? {
      if let catalogProgram { return catalogProgram.prepareControlUpdate(parameters: parameters) }
      return prepareLegacyControlUpdate(parameters: parameters)
    }

    private func prepareLegacyControlUpdate(parameters: [String: Any]) -> SceneCatalogControlUpdate? {
      guard let currentIdentity = SceneCatalogControlUpdatePlan.controlIdentity(originalParameters),
        currentIdentity == SceneCatalogControlUpdatePlan.controlIdentity(parameters),
        let next = Self.parse(parameters: parameters, loadImage: true) else { return nil }
      let previousNode = node
      let previousParameters = originalParameters
      let previousNeon = neonPulse, previousStars = magicStars
      let previousStrobe = strobe
      let previousHideAt = flashHideAt
      let previousAwaitingPublication = flashAwaitingPublication
      let previousCleanupAwaitingPublication = flashCleanupAwaitingPublication
      var replacementNeon = previousNeon
      var replacementStars = previousStars
      var replacementStrobe = previousStrobe
      switch (node, next) {
      case (.neonPulse, .neonPulse(let layer)):
        guard let neonPulse else { return nil }
        replacementNeon = neonPulse.copyingControls(layer.controls)
      case (.magicStars, .magicStars(let layer)):
        guard let magicStars else { return nil }
        replacementStars = magicStars.copyingControls(layer.controls)
      case (.strobe, .strobe(let layer, _)):
        guard let strobe else { return nil }
        replacementStrobe = strobe.copyingControls(layer: layer)
      default: return nil
      }
      return SceneCatalogControlUpdate(apply: { [weak self] in
        self?.node = next; self?.originalParameters = parameters
        self?.neonPulse = replacementNeon; self?.magicStars = replacementStars
        self?.strobe = replacementStrobe
        if replacementStrobe?.isTimedFlashVisible == false {
          self?.flashHideAt = nil
          self?.flashAwaitingPublication = false
          self?.flashCleanupAwaitingPublication = false
        }
      }, rollback: { [weak self] in
        self?.node = previousNode; self?.originalParameters = previousParameters
        self?.neonPulse = previousNeon; self?.magicStars = previousStars
        self?.strobe = previousStrobe
        self?.flashHideAt = previousHideAt
        self?.flashAwaitingPublication = previousAwaitingPublication
        self?.flashCleanupAwaitingPublication = previousCleanupAwaitingPublication
      })
    }

    var usesAuthoredSourceOver: Bool { catalogProgram != nil }

    var preferredFramesPerSecond: Int {
      if let catalogProgram { return catalogProgram.preferredFramesPerSecond }
      if strobe != nil { return 60 }
      return node?.framesPerSecond(for: "best") ?? 0
    }

    /// A deferred CI source with an authored slow cadence can amortize a
    /// raster across faster sibling frames. Cheap static fills (0 Hz), Metal
    /// output textures and event-driven strobes must not acquire extra passes.
    var supportsStableSourceRasterReuse: Bool {
      catalogProgram == nil && outputAllocator == nil && strobe == nil &&
        preferredFramesPerSecond > 0 && preferredFramesPerSecond <= 1
    }

    var needsContinuousRendering: Bool {
      guard playing else { return false }
      if let catalogProgram { return catalogProgram.needsContinuousRendering }
      if let strobe {
        return strobe.hasClockCadence || strobe.transitionActive || flashAwaitingPublication ||
          flashCleanupAwaitingPublication || flashHideAt != nil
      }
      if let radialProfile { return radialProfile.active }
      switch node {
      case .solidColor, .blueSky, .embeddedScreen, .waveform: return false
      default: return preferredFramesPerSecond > 0
      }
    }

    @discardableResult
    func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
      guard playing else { return false }
      if signalSessionID != frame.sessionId {
        signalSessionID = frame.sessionId
        signalSequence = -1
      }
      guard frame.sequence > signalSequence else { return false }
      signalSequence = frame.sequence
      if let catalogProgram { return catalogProgram.consume(frame) }
      if let strobe {
        let changed = strobe.consume(frame)
        if changed && strobe.program == .transparentProStrobe {
          flashAwaitingPublication = true
          flashHideAt = nil
          flashCleanupAwaitingPublication = false
        }
        return changed
      }
      if let radialProfile {
        return radialProfile.consume(frame, hostTime: CACurrentMediaTime())
      }
      if let radialWarp { return radialWarp.consume(frame) }
      if let paintedStarlight { return paintedStarlight.consume(frame) }
      if let magicStars { return magicStars.consume(frame) }
      if let radiantEmission { return radiantEmission.consume(frame) }
      if let rainbowWaterfall { return rainbowWaterfall.consume(frame) }
      if let neonPulse { return neonPulse.consume(frame) }
      if case .embeddedScreen(let layer) = node, let embeddedScreen {
        return embeddedScreen.consume(frame, layer: layer)
      }
      if case .waveform(let layer) = node, let waveform {
        return waveform.consume(frame, layer: layer)
      }
      return false
    }

    func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
      guard next != playing else { return }
      playing = next
      lastHostTime = next ? hostTime : nil
      catalogProgram?.setPlaying(next, hostTime: hostTime)
      strobe?.setPlaying(next)
      radialProfile?.setPlaying(next, hostTime: hostTime)
      radialWarp?.setPlaying(next, hostTime: hostTime)
      snowfall?.setPlaying(next, hostTime: hostTime)
      paintedStarlight?.setPlaying(next, hostTime: hostTime)
      magicStars?.setPlaying(next, hostTime: hostTime)
      magicMoon?.setPlaying(next, hostTime: hostTime)
      radiantEmission?.setPlaying(next, hostTime: hostTime)
      rainbowWaterfall?.setPlaying(next, hostTime: hostTime)
      neonPulse?.setPlaying(next, hostTime: hostTime)
    }

    /// Called by V1 only after the complete composition was published. Failed
    /// renders cannot consume the visible duration of an admitted flash.
    func didPublish(hostTime: CFTimeInterval) {
      flashCleanupAwaitingPublication = false
      if flashAwaitingPublication {
        flashAwaitingPublication = false
        flashHideAt = hostTime + (strobe?.flashDurationSeconds ?? 0.1)
      }
    }

    func render(target: CGRect, hostTime: CFTimeInterval) -> CIImage? {
      guard target.width.isFinite, target.height.isFinite,
            target.width >= 1, target.height >= 1,
            target.width <= 8192, target.height <= 8192 else { return nil }
      let pointScale = Float(min(
        target.width / logicalSize.width, target.height / logicalSize.height
      ))
      let reducedMotion = UIAccessibility.isReduceMotionEnabled
      if let catalogProgram {
        return try? catalogProgram.render(target: target, hostTime: hostTime,
          reducedMotion: reducedMotion)
      }
      guard let node else { return nil }
      if playing {
        if let previous = lastHostTime {
          _ = strobe?.advance(by: Int64(max(0, hostTime - previous) * 1_000_000))
        }
        lastHostTime = hostTime
        if let hideAt = flashHideAt, hostTime >= hideAt {
          flashCleanupAwaitingPublication = strobe?.hideTimedFlash() == true
          flashHideAt = nil
        }
        _ = radialProfile?.advance(hostTime: hostTime)
        _ = radialWarp?.advance(hostTime: hostTime)
        _ = snowfall?.advance(hostTime: hostTime)
        _ = paintedStarlight?.advance(hostTime: hostTime)
        _ = magicStars?.advance(hostTime: hostTime)
        _ = magicMoon?.advance(hostTime: hostTime)
        _ = radiantEmission?.advance(hostTime: hostTime)
        _ = rainbowWaterfall?.advance(
          hostTime: hostTime, motionRateScale: reducedMotion ? 0.35 : 1
        )
        _ = neonPulse?.advance(hostTime: hostTime)
      }
      // Heap outputs remain immutable while any derived CIImage retains them.
      // The component owner releases obsolete preparation before replacement.
      do {
        switch node {
        case .solidColor:
          return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: target)
        case .strobe:
          return strobe?.render(target: target)
        case .blueSky(let layer):
          return Library.renderBlueSkyLayer(layer, target: target)
        case .radialProfile(let layer):
          guard let radialProfile else { return nil }
          return try Library.renderRadialProfileLayer(layer, state: radialProfile,
            target: target, reducedMotion: reducedMotion)
        case .radialWarp(let layer):
          guard let radialWarp, let graphics else { return nil }
          return try Library.renderRadialWarpLayer(graphics: graphics, layer,
            state: radialWarp, quality: "best", target: target, device: graphics.device,
            outputAllocator: outputAllocator)
        case .snowfall(let layer):
          guard let snowfall else { return nil }
          return try Library.renderSnowfallLayer(graphics: graphics, layer,
            state: snowfall, quality: "best", pointScale: pointScale, target: target,
            outputAllocator: outputAllocator)
        case .paintedStarlight(let layer):
          guard let paintedStarlight else { return nil }
          return try Library.renderPaintedStarlightLayer(graphics: graphics, layer,
            state: paintedStarlight, quality: "best", target: target,
            outputAllocator: outputAllocator)
        case .magicStars(let layer):
          guard let magicStars else { return nil }
          return try Library.renderMagicStarsLayer(graphics: graphics, layer,
            state: magicStars, quality: "best", pointScale: pointScale, target: target,
            outputAllocator: outputAllocator)
        case .magicMoon(let layer):
          guard let magicMoon else { return nil }
          return try Library.renderMagicMoonLayer(layer, state: magicMoon, target: target)
        case .radiantEmission(let layer):
          guard let radiantEmission else { return nil }
          return try Library.renderRadiantEmissionLayer(layer, state: radiantEmission,
            quality: "best", target: target, reducedMotion: reducedMotion)
        case .rainbowWaterfall(let layer):
          guard let rainbowWaterfall else { return nil }
          return try Library.renderRainbowWaterfallLayer(layer, state: rainbowWaterfall,
            target: target, reducedMotion: reducedMotion)
        case .neonPulse(let layer):
          guard let neonPulse else { return nil }
          return try Library.renderNeonPulseLayer(graphics: graphics, layer,
            state: neonPulse, quality: "best", pointScale: pointScale, target: target,
            outputAllocator: outputAllocator)
        case .embeddedScreen(let layer):
          guard let embeddedScreen else { return nil }
          return try Library.renderEmbeddedScreenLayer(graphics: graphics, layer,
            state: embeddedScreen, quality: "best", target: target,
            outputAllocator: outputAllocator)
        case .waveform(let layer):
          guard let waveform else { return nil }
          return try Library.renderWaveformLayer(graphics: graphics, layer,
            state: waveform, quality: "best", pointScale: pointScale, target: target,
            outputAllocator: outputAllocator)
        case .image, .media, .installedProgram: return nil
        }
      } catch {
        return nil // V1 treats a missing source as a failed composition.
      }
    }
  }

  private final class GraphicsResources {
    let device: MTLDevice
    let ciContext: CIContext
    lazy var radialWarpRenderer = try? SceneRenderV2RadialWarpMetalRenderer(
      device: device
    )
    lazy var snowfallRenderer = try? SceneRenderV2SnowfallMetalRenderer(
      device: device
    )
    lazy var paintedStarlightRenderer =
      try? SceneRenderV2PaintedStarlightMetalRenderer(device: device)
    lazy var magicStarsRenderer = try? SceneRenderV2MagicStarsMetalRenderer(
      device: device
    )
    lazy var neonPulseRenderer = try? SceneRenderV2NeonPulseMetalRenderer(
      device: device
    )
    lazy var embeddedScreenRenderer =
      try? SceneRenderV2EmbeddedScreenMetalRenderer(device: device)
    lazy var waveformRenderer = try? SceneRenderV2WaveformMetalRenderer(
      device: device
    )

    init(device: MTLDevice, ciContext: CIContext) {
      self.device = device
      self.ciContext = ciContext
    }
  }

  private enum StrobeProgram: String {
    case backgroundBlackWhite = "b_bw"
    case backgroundColorLights = "b_colorlights"
    case backgroundProColorful = "b_pro_colorful"
    case backgroundSimpleDisco = "b_simple_disco"
    case transparentBlackWhite = "t_bw"
    case transparentProStrobe = "t_pro_strobe"

    var audioReactive: Bool {
      switch self {
      case .backgroundProColorful, .backgroundSimpleDisco,
           .transparentProStrobe: true
      default: false
      }
    }

    var logicalIntervalMicros: Int64? {
      switch self {
      case .backgroundBlackWhite, .backgroundColorLights: 50_000
      case .transparentBlackWhite: 500_000
      default: nil
      }
    }
  }

  private struct StrobeLayer {
    let id: String
    let program: StrobeProgram
    let opacity: CGFloat
    let options: StrobeOptions
  }

  private struct StrobeOptions: Equatable {
    var intervalMicros: Int64?
    var smooth = false
    var showBlack = true
    var brightness: CGFloat = 1
    var speed = 1.0
    var flashDuration = 0.1
    var transparentWhite = false
    var transparentBlack = false
    var rotation = false
    var scale = false
    var gradient = false
    var spark = false
    var rainbow = false
    var brightRainbow = false
    var intense = false
    var modeIdentity = "default"

    var transitionMicros: Int64 {
      guard smooth else { return 0 }
      if let intervalMicros { return max(1_000, (intervalMicros / 2_000) * 1_000) }
      return Int64((1_000 / speed).rounded()) * 1_000
    }

    var flashDurationSeconds: Double {
      min(250, max(45, (flashDuration * 1_000 / speed).rounded())) / 1_000
    }
  }

  private struct StrobeFrame: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
    var gradientEnd: [CGFloat]? = nil
    var rotation: CGFloat = 0
    var scale: CGFloat = 1

    func render(target: CGRect, opacity: CGFloat = 1) -> CIImage? {
      let color = CIColor(red: red, green: green, blue: blue, alpha: alpha * opacity)
      var image: CIImage
      if let end = gradientEnd {
        guard let gradient = CIFilter(name: "CILinearGradient", parameters: [
          "inputPoint0": CIVector(x: target.minX, y: target.midY),
          "inputPoint1": CIVector(x: target.maxX, y: target.midY),
          "inputColor0": color,
          "inputColor1": CIColor(red: end[0], green: end[1], blue: end[2], alpha: end[3] * opacity),
        ])?.outputImage else { return nil }
        image = gradient.cropped(to: target)
      } else {
        image = CIImage(color: color).cropped(to: target)
      }
      if rotation != 0 || scale != 1 {
        image = image.transformed(by: CGAffineTransform(
          translationX: target.midX, y: target.midY
        ).rotated(by: -rotation).scaledBy(x: scale, y: scale)
          .translatedBy(x: -target.midX, y: -target.midY))
      }
      return image.cropped(to: target)
    }
  }

  private enum GraphNode {
    case solidColor(id: String, opacity: CGFloat, renderScales: [String: Double])
    case image(ImageLayer, renderScales: [String: Double])
    case media(MediaLayer)
    case strobe(StrobeLayer, renderScales: [String: Double])
    case radialProfile(SceneRenderV2RadialProfileLayer)
    case radialWarp(SceneRenderV2RadialWarpLayer)
    case snowfall(SceneRenderV2SnowfallLayer)
    case paintedStarlight(SceneRenderV2PaintedStarlightLayer)
    case magicStars(SceneRenderV2MagicStarsLayer)
    case blueSky(SceneRenderV2BlueSkyLayer)
    case magicMoon(SceneRenderV2MagicMoonLayer)
    case radiantEmission(SceneRenderV2RadiantEmissionLayer)
    case rainbowWaterfall(SceneRenderV2RainbowWaterfallLayer)
    case neonPulse(SceneRenderV2NeonPulseLayer)
    case embeddedScreen(SceneRenderV2EmbeddedScreenLayer)
    case waveform(SceneRenderV2WaveformLayer)
    case installedProgram(SceneRenderV2InstalledProgramLayer)

    var renderScales: [String: Double] {
      switch self {
      case .solidColor(_, _, let scales): scales
      case .image(_, let scales), .strobe(_, let scales): scales
      case .media(let layer): layer.renderScales
      case .radialProfile(let layer): layer.renderScales
      case .radialWarp(let layer): layer.renderScales
      case .snowfall(let layer): layer.renderScales
      case .paintedStarlight(let layer): layer.renderScales
      case .magicStars(let layer): layer.renderScales
      case .blueSky(let layer): layer.renderScales
      case .magicMoon(let layer): layer.renderScales
      case .radiantEmission(let layer): layer.renderScales
      case .rainbowWaterfall(let layer): layer.renderScales
      case .neonPulse(let layer): layer.renderScales
      case .embeddedScreen(let layer): layer.renderScales
      case .waveform(let layer): layer.renderScales
      case .installedProgram(let layer): layer.renderScales
      }
    }

    var targetFramesPerSecond: Int {
      switch self {
      case .solidColor: 1
      case .image(let layer, _):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .media(let layer): layer.framesPerSecondByQuality.values.max() ?? 1
      case .strobe: 60
      case .radialProfile(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .radialWarp(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .snowfall(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .paintedStarlight(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .magicStars(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .blueSky: 1
      case .magicMoon(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .radiantEmission(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .rainbowWaterfall(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .neonPulse(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .embeddedScreen(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .waveform(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      case .installedProgram(let layer):
        layer.framesPerSecondByQuality.values.max() ?? 1
      }
    }

    func framesPerSecond(for quality: String) -> Int {
      switch self {
      case .solidColor: return 0
      case .image(let layer, _):
        return layer.naturalReactiveLight == nil
          ? 0
          : layer.framesPerSecondByQuality[quality] ?? 1
      case .media(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .strobe(let layer, _):
        guard let interval = layer.program.logicalIntervalMicros else { return 0 }
        return max(1, Int((1_000_000.0 / Double(interval)).rounded()))
      case .radialProfile(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .radialWarp(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .snowfall(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .paintedStarlight(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .magicStars(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .blueSky: return 0
      case .magicMoon(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .radiantEmission(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .rainbowWaterfall(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .neonPulse(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .embeddedScreen(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .waveform(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      case .installedProgram(let layer):
        return layer.framesPerSecondByQuality[quality] ?? 1
      }
    }

    func pictureInPictureFramesPerSecond(for quality: String) -> Int {
      // Event-driven nodes have no continuous render cadence, but the PiP
      // consumer must sample their published changes at the authored rate.
      if case .strobe(let layer, _) = self, layer.program.audioReactive {
        return targetFramesPerSecond
      }
      return max(1, framesPerSecond(for: quality))
    }
  }

  private enum MediaKind: String {
    case animatedImage = "media.animatedImage"
    case video = "media.video"
    case straightAlphaVideo = "media.straightAlphaVideo"
    case packedAlphaVideo = "media.packedAlphaVideo"

    var resourceKind: String {
      switch self {
      case .animatedImage: "animatedImage"
      case .video: "video"
      case .straightAlphaVideo: "straightAlphaVideo"
      case .packedAlphaVideo: "packedAlphaVideo"
      }
    }

    var alphaMode: String {
      switch self {
      case .video, .animatedImage: "normal"
      case .straightAlphaVideo: "straightAlpha"
      case .packedAlphaVideo: "packedSideBySide"
      }
    }

    var transitionStrategy: String {
      self == .animatedImage ? "cadenceLocked" : "alignedMediaTrack"
    }

    var isVideo: Bool { self != .animatedImage }
  }

  private struct MediaLayer {
    let id: String
    let kind: MediaKind
    let url: URL
    let resourceIdentity: String
    let opacity: CGFloat
    let width: CGFloat
    let height: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let scale: CGFloat
    let rotation: CGFloat
    let flipped: Bool
    let playbackRate: Float
    let renderScales: [String: Double]
    let framesPerSecondByQuality: [String: Int]
    let naturalReactiveLight: SceneRenderV2NaturalReactiveLightConfig?
    let rgbGain: SceneRenderV2RGBGainConfig?
  }

  private struct ImageLayer {
    let id: String
    let source: CIImage
    let opacity: CGFloat
    let width: CGFloat
    let height: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let scale: CGFloat
    let rotation: CGFloat
    let flipped: Bool
    let framesPerSecondByQuality: [String: Int]
    let naturalReactiveLight: SceneRenderV2NaturalReactiveLightConfig?
  }

  private struct FilterTone: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let amount: CGFloat
  }

  private struct FilterGrade: Equatable {
    let filterID: String
    var intensity: CGFloat
    let exposure: CGFloat
    let contrast: CGFloat
    let saturation: CGFloat
    let vibrance: CGFloat
    let temperature: CGFloat
    let tint: CGFloat
    let blackLift: CGFloat
    let highlightRolloff: CGFloat
    let shadowDepth: CGFloat
    let midtoneBalance: CGFloat
    let colorDensity: CGFloat
    let cyanPresence: CGFloat
    let magentaPresence: CGFloat
    let goldPresence: CGFloat
    let shadows: FilterTone
    let midtones: FilterTone
    let highlights: FilterTone
    let vignette: CGFloat
    let vignetteSoftness: CGFloat
  }


  /// Exact authored grade used as the final operation of the existing scene.
  /// No texture, decoder, timer or audio owner is created here.
  struct NativeFilter: Equatable {
    private var grade: FilterGrade
    private init(grade: FilterGrade) { self.grade = grade }

    init?(definition: [String: Any]) {
      guard Set(definition.keys) == Set(["id", "intensity", "parameters"]),
        let id = definition["id"] as? String, validToken(id),
        let intensity = bounded(definition["intensity"], minimum: 0, maximum: 1),
        let values = definition["parameters"] as? [String: Any],
        let grade = parseFilterValues(values, filterID: id, intensity: intensity),
        filterGradeKernel != nil else { return nil }
      self.grade = grade
    }

    static let identity = NativeFilter(grade: FilterGrade(
      filterID: "identity",
      intensity: 0,
      exposure: 0,
      contrast: 1,
      saturation: 1,
      vibrance: 0,
      temperature: 0,
      tint: 0,
      blackLift: 0,
      highlightRolloff: 0,
      shadowDepth: 0,
      midtoneBalance: 0,
      colorDensity: 0,
      cyanPresence: 0,
      magentaPresence: 0,
      goldPresence: 0,
      shadows: FilterTone(red: 1, green: 1, blue: 1, amount: 0),
      midtones: FilterTone(red: 1, green: 1, blue: 1, amount: 0),
      highlights: FilterTone(red: 1, green: 1, blue: 1, amount: 0),
      vignette: 0, vignetteSoftness: 0.7
    ))
    var inactive: Bool { grade.intensity <= 0.0001 }
    func sameParameters(as other: Self) -> Bool {
      var lhs = grade, rhs = other.grade
      lhs.intensity = 0; rhs.intensity = 0
      return lhs == rhs
    }
    func interpolated(to next: Self, progress: Double) -> Self {
      let t = CGFloat(min(max(progress, 0), 1))
      func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
      func tone(_ a: FilterTone, _ b: FilterTone) -> FilterTone {
        func encoded(_ x: CGFloat) -> CGFloat {
          x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        func color(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
          // Flutter Color.lerp interpolates encoded 8-bit channels.
          let channel = (mix(encoded(a), encoded(b)) * 255).rounded() / 255
          return srgbToLinear(channel)
        }
        return FilterTone(red: color(a.red, b.red), green: color(a.green, b.green),
          blue: color(a.blue, b.blue), amount: mix(a.amount, b.amount))
      }
      return Self(grade: FilterGrade(
        filterID: next.grade.filterID,
        intensity: mix(grade.intensity, next.grade.intensity),
        exposure: mix(grade.exposure, next.grade.exposure),
        contrast: mix(grade.contrast, next.grade.contrast),
        saturation: mix(grade.saturation, next.grade.saturation),
        vibrance: mix(grade.vibrance, next.grade.vibrance),
        temperature: mix(grade.temperature, next.grade.temperature),
        tint: mix(grade.tint, next.grade.tint),
        blackLift: mix(grade.blackLift, next.grade.blackLift),
        highlightRolloff: mix(grade.highlightRolloff, next.grade.highlightRolloff),
        shadowDepth: mix(grade.shadowDepth, next.grade.shadowDepth),
        midtoneBalance: mix(grade.midtoneBalance, next.grade.midtoneBalance),
        colorDensity: mix(grade.colorDensity, next.grade.colorDensity),
        cyanPresence: mix(grade.cyanPresence, next.grade.cyanPresence),
        magentaPresence: mix(grade.magentaPresence, next.grade.magentaPresence),
        goldPresence: mix(grade.goldPresence, next.grade.goldPresence),
        shadows: tone(grade.shadows, next.grade.shadows),
        midtones: tone(grade.midtones, next.grade.midtones),
        highlights: tone(grade.highlights, next.grade.highlights),
        vignette: mix(grade.vignette, next.grade.vignette),
        vignetteSoftness: mix(grade.vignetteSoftness, next.grade.vignetteSoftness)
      ))
    }
    func render(_ input: CIImage, target: CGRect) -> CIImage? {
      if inactive { return input }
      let filter = grade
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      guard let encoded = input.matchedFromWorkingSpace(to: colorSpace),
        let filtered = filterGradeKernel?.apply(extent: target, arguments: [
            encoded,
            CIVector(x: target.origin.x, y: target.origin.y),
            CIVector(x: target.width, y: target.height),
            filter.intensity,
            filter.exposure,
            filter.contrast,
            filter.saturation,
            filter.vibrance,
            filter.temperature,
            filter.tint,
            filter.blackLift,
            filter.highlightRolloff,
            filter.shadowDepth,
            filter.midtoneBalance,
            filter.colorDensity,
            filter.cyanPresence,
            filter.magentaPresence,
            filter.goldPresence,
            CIVector(
              x: filter.shadows.red,
              y: filter.shadows.green,
              z: filter.shadows.blue
            ),
            filter.shadows.amount,
            CIVector(
              x: filter.midtones.red,
              y: filter.midtones.green,
              z: filter.midtones.blue
            ),
            filter.midtones.amount,
            CIVector(
              x: filter.highlights.red,
              y: filter.highlights.green,
              z: filter.highlights.blue
            ),
            filter.highlights.amount,
            filter.vignette,
            filter.vignetteSoftness,
          ]),
        let result = filtered.matchedToWorkingSpace(from: colorSpace)
      else { return nil }
      return result.cropped(to: target)
    }
  }

  struct NativeFilterTransition {
    private(set) var value: NativeFilter
    private var from: NativeFilter
    private var target: NativeFilter
    private var started: CFTimeInterval?
    var active: Bool { started != nil }
    var needsGrade: Bool { active || !value.inactive }
    init(_ filter: NativeFilter) { value = filter; from = filter; target = filter }
    mutating func update(to next: NativeFilter, at now: CFTimeInterval) {
      if target.sameParameters(as: next) {
        target = next
        if !active { from = next; value = next }
      } else {
        advance(at: now)
        from = value; target = next; started = now
      }
    }
    mutating func advance(at now: CFTimeInterval) {
      guard let start = started else { value = target; return }
      let t = min(max((now - start) / 0.18, 0), 1)
      // Flutter Curves.easeOutCubic is cubic-bezier(0.215, 0.61, 0.355, 1).
      var lo = 0.0, hi = 1.0
      for _ in 0..<20 {
        let m = (lo + hi) * 0.5, u = 1 - m
        let x = 3 * u * u * m * 0.215 + 3 * u * m * m * 0.355 + m * m * m
        if x < t { lo = m } else { hi = m }
      }
      let m = (lo + hi) * 0.5, u = 1 - m
      let eased = t == 1 ? 1 : 3 * u * u * m * 0.61 + 3 * u * m * m + m * m * m
      value = from.interpolated(to: target, progress: eased)
      if t >= 1 { value = target; from = target; started = nil }
    }
  }

  private final class Texture: NSObject, FlutterTexture {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    func publish(_ buffer: CVPixelBuffer) {
      lock.lock()
      self.buffer = buffer
      lock.unlock()
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
      lock.lock()
      defer { lock.unlock() }
      guard let buffer else { return nil }
      return Unmanaged.passRetained(buffer)
    }

    func latestPixelBuffer() -> CVPixelBuffer? {
      lock.lock()
      defer { lock.unlock() }
      return buffer
    }

    func onTextureUnregistered(_ texture: FlutterTexture) {
      lock.lock()
      buffer = nil
      lock.unlock()
    }
  }

  private struct BufferPoolKey: Hashable {
    let width: Int
    let height: Int
  }

  private struct Plan {
    let sessionID: String
    let document: [String: Any]
    let semanticPlanHash: String
    let qualityPlanHashes: [String: String]
    let registryRevision: String
    var quality: String
    var width: Double
    var height: Double
    var devicePixelRatio: Double
    var playing: Bool
    let mediaPtsMicros: Int64
    let sessionSeed: UInt32
    let nodes: [GraphNode]
    let filter: FilterGrade?

    var qualityPlanHash: String { qualityPlanHashes[quality]! }
    var renderScale: Double {
      nodes.compactMap { $0.renderScales[quality] }.max() ?? 1
    }
    var targetFramesPerSecond: Int {
      nodes.map(\.targetFramesPerSecond).max() ?? 1
    }
    var continuousFramesPerSecond: Int {
      nodes.map { $0.framesPerSecond(for: quality) }.max() ?? 0
    }
    var pictureInPictureFramesPerSecond: Int {
      nodes.map { $0.pictureInPictureFramesPerSecond(for: quality) }.max() ?? 1
    }
    var pixelWidth: Int {
      min(4096, max(1, Int((width * devicePixelRatio * renderScale).rounded())))
    }
    var pixelHeight: Int {
      min(4096, max(1, Int((height * devicePixelRatio * renderScale).rounded())))
    }
  }

  private struct ParsedDocument {
    let nodes: [GraphNode]
    let filter: FilterGrade?
  }

  private final class PendingSignalPresentation {
    let sequence: Int64
    let deadlineNanos: UInt64
    let hasTimedFlash: Bool
    let result: FlutterResult

    init(
      sequence: Int64,
      deadlineNanos: UInt64,
      hasTimedFlash: Bool,
      result: @escaping FlutterResult
    ) {
      self.sequence = sequence
      self.deadlineNanos = deadlineNanos
      self.hasTimedFlash = hasTimedFlash
      self.result = result
    }
  }

  private final class PendingRecoveryPresentation {
    var plan: Plan
    let mediaStates: [String: MediaState]
    let mediaCommitGate = SceneRenderV2MediaCommitGate()
    let preparationTicket: UInt64
    let replacementGraphics: GraphicsResources
    let previousRendererAcceptingFrames: Bool
    var deadlineNanos: UInt64
    let result: FlutterResult

    init(
      plan: Plan,
      mediaStates: [String: MediaState],
      preparationTicket: UInt64,
      replacementGraphics: GraphicsResources,
      previousRendererAcceptingFrames: Bool,
      deadlineNanos: UInt64,
      result: @escaping FlutterResult
    ) {
      self.plan = plan
      self.mediaStates = mediaStates
      self.preparationTicket = preparationTicket
      self.replacementGraphics = replacementGraphics
      self.previousRendererAcceptingFrames = previousRendererAcceptingFrames
      self.deadlineNanos = deadlineNanos
      self.result = result
    }
  }

  private final class Session {
    let texture: Texture
    let textureID: Int64
    var plan: Plan
    var submitted = 0
    var completed = 0
    var metricsSequence = 0
    var latestSignalSequence: Int64 = -1
    var signalStateNeedsPresentation = false
    var completeFramePresented = false
    var rendererAcceptingFrames = true
    var lastMetricsNanos = DispatchTime.now().uptimeNanoseconds
    var lastMetricsCompleted = 0
    var lastMetricsCadenceNoChangeTicks = 0
    var lastMetricsCadenceSkippedPeriods = 0
    var lastMetricsBackpressureEvents = 0
    var cumulativeAuthoredDeadlines = 0
    var cumulativeRenderedFrames = 0
    var cumulativeDeadlineMisses = 0
    var cumulativeMaximumConsecutiveDeadlineMisses = 0
    var cadenceTicks = 0
    var cadenceSkippedPeriods = 0
    var cadenceNoChangeTicks = 0
    var cadenceRenders = 0
    var signalRenders = 0
    var signalUpdates = 0
    var cumulativeSignalProcessingMicros = 0
    var maximumSignalProcessingMicros = 0
    var maximumCadenceLatenessMicros = 0
    var cumulativeRenderMicros = 0
    var maximumRenderMicros = 0
    var overBudgetRenders = 0
    var renderCount = 0
    var renderMicros = [Int]()
    var consecutiveRenderFailures = 0
    var maximumConsecutiveRenderFailures = 0
    var strobeStates = [String: StrobeState]()
    var imageReactiveStates = [String: SceneRenderV2NaturalReactiveLightState]()
    var mediaStates = [String: MediaState]()
    var mediaCommitGate = SceneRenderV2MediaCommitGate()
    var radialProfileStates = [String: SceneRenderV2RadialProfileState]()
    var radialWarpStates = [String: SceneRenderV2RadialWarpState]()
    var snowfallStates = [String: SceneRenderV2SnowfallState]()
    var paintedStarlightStates = [String: SceneRenderV2PaintedStarlightState]()
    var magicStarsStates = [String: SceneRenderV2MagicStarsState]()
    var magicMoonStates = [String: SceneRenderV2MagicMoonState]()
    var radiantEmissionStates = [String: SceneRenderV2RadiantEmissionState]()
    var rainbowWaterfallStates = [String: SceneRenderV2RainbowWaterfallState]()
    var neonPulseStates = [String: SceneRenderV2NeonPulseState]()
    var embeddedScreenStates = [String: SceneRenderV2EmbeddedScreenState]()
    var waveformStates = [String: SceneRenderV2WaveformState]()
    var installedProgramStates = [String: SceneRenderV2InstalledProgramState]()
    var bufferPools = [BufferPoolKey: CVPixelBufferPool]()
    var pixelBufferBackpressureEvents = 0
    let presentationArbiter = SceneRenderV2PresentationArbiter()
    var pendingSignalPresentation: PendingSignalPresentation?
    var pendingRecoveryPresentation: PendingRecoveryPresentation?
    var cadenceTimer: DispatchSourceTimer?
    var presentationDeadlineNanos: UInt64 = 0
    var cadenceDeadlineNanos: UInt64 = 0
    var lastCadenceTickNanos: UInt64 = 0
    var flashWorkItem: DispatchWorkItem?
    var flashRestoreBuffer: CVPixelBuffer?
    var flashHideStartedNanos: UInt64 = 0
    var foregroundPlaying: Bool
    var pictureInPicturePlaying = false
    var pictureInPictureRetainCount = 0
    var foregroundAttached = true
    var flutterTextureRegistered = true
    var qualityActivatedAtNanos = DispatchTime.now().uptimeNanoseconds

    init(
      texture: Texture,
      textureID: Int64,
      plan: Plan,
      mediaStates: [String: MediaState],
      installedProgramStates: [String: SceneRenderV2InstalledProgramState]
    ) {
      self.texture = texture
      self.textureID = textureID
      self.plan = plan
      foregroundPlaying = plan.playing
      self.mediaStates = mediaStates
      self.installedProgramStates = installedProgramStates
      for node in plan.nodes {
        if case .image(let layer, _) = node,
                  let config = layer.naturalReactiveLight {
          imageReactiveStates[layer.id] = SceneRenderV2NaturalReactiveLightState(
            config: config
          )
        } else if case .strobe(let layer, _) = node {
          strobeStates[layer.id] = StrobeState(plan: plan, layer: layer)
        } else if case .radialProfile(let layer) = node {
          radialProfileStates[layer.id] = SceneRenderV2RadialProfileState(layer: layer)
        } else if case .radialWarp(let layer) = node {
          let state = SceneRenderV2RadialWarpState(layerID: layer.id)
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          radialWarpStates[layer.id] = state
        } else if case .snowfall(let layer) = node {
          let state = SceneRenderV2SnowfallState(layerID: layer.id)
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          snowfallStates[layer.id] = state
        } else if case .paintedStarlight(let layer) = node {
          let state = SceneRenderV2PaintedStarlightState(layerID: layer.id)
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          paintedStarlightStates[layer.id] = state
        } else if case .magicStars(let layer) = node {
          let state = SceneRenderV2MagicStarsState(
            layerID: layer.id,
            sessionSeed: plan.sessionSeed
          )
          state.applyControls(layer.controls)
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          magicStarsStates[layer.id] = state
        } else if case .magicMoon(let layer) = node {
          let state = SceneRenderV2MagicMoonState(layerID: layer.id)
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          magicMoonStates[layer.id] = state
        } else if case .radiantEmission(let layer) = node {
          let state = SceneRenderV2RadiantEmissionState(layerID: layer.id)
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          radiantEmissionStates[layer.id] = state
        } else if case .rainbowWaterfall(let layer) = node {
          let state = SceneRenderV2RainbowWaterfallState(layerID: layer.id)
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          rainbowWaterfallStates[layer.id] = state
        } else if case .neonPulse(let layer) = node {
          let state = SceneRenderV2NeonPulseState(
            layerID: layer.id,
            sessionSeed: plan.sessionSeed
          )
          state.controls = layer.controls
          state.setPlaying(plan.playing, hostTime: CACurrentMediaTime())
          neonPulseStates[layer.id] = state
        } else if case .embeddedScreen(let layer) = node {
          embeddedScreenStates[layer.id] = SceneRenderV2EmbeddedScreenState(
            layerID: layer.id
          )
        } else if case .waveform(let layer) = node {
          waveformStates[layer.id] = SceneRenderV2WaveformState(layerID: layer.id)
        }
      }
    }
  }

  private final class StrobeState {
    private var playing: Bool
    private(set) var layer: StrobeLayer
    private var elapsedMicros: Int64 = 0
    private var lastLogicalStep: Int64 = 0
    private var colorIndex = 0
    private var lastFlashSerial: Int64 = -1
    private var signalSessionID: Int64 = -1
    private var flashVisible = false
    private var lastFlashStrength: CGFloat = 1
    private var normalizedMotion: Float = 0
    private var currentColor: StrobeFrame
    private var animationFrom: StrobeFrame
    private var animationTo: StrobeFrame
    private var animationElapsedMicros: Int64 = 0
    private var animationDurationMicros: Int64 = 0
    private var animationFresh = false
    private var rotation: CGFloat = 0
    private var scale: CGFloat = 1
    private(set) var frame: StrobeFrame

    var program: StrobeProgram { layer.program }
    var hasClockCadence: Bool {
      layer.options.intervalMicros != nil || animationElapsedMicros < animationDurationMicros
    }
    var transitionActive: Bool { animationElapsedMicros < animationDurationMicros }
    var flashDurationSeconds: Double { layer.options.flashDurationSeconds }
    var isTimedFlashVisible: Bool { flashVisible }

    func render(target: CGRect) -> CIImage? { frame.render(target: target) }

    convenience init(plan: Plan, layer: StrobeLayer) {
      self.init(layer: layer, playing: plan.playing)
    }

    init(layer: StrobeLayer, playing: Bool) {
      self.playing = playing
      self.layer = layer
      let first = Self.palette(layer).first!
      currentColor = first
      animationFrom = first
      animationTo = first
      frame = first
      if layer.program == .transparentProStrobe {
        frame = Self.transparent
      } else if layer.program == .transparentBlackWhite {
        frame = Self.transparent
      } else if layer.program.logicalIntervalMicros != nil, layer.options.showBlack {
        frame = Self.black
      } else {
        frame = decoratedColor(first)
      }
      if layer.program == .backgroundSimpleDisco || layer.program == .backgroundProColorful {
        animationFrom = frame
        animationTo = frame
      }
    }

    func setPlaying(_ playing: Bool) { self.playing = playing }

    func rebind(plan: Plan, layer: StrobeLayer) {
      precondition(layer.program == self.layer.program && layer.id == self.layer.id)
      playing = plan.playing
      self.layer = layer
    }

    /// Preparing controls never mutates the currently published state.
    func copyingControls(layer next: StrobeLayer) -> StrobeState {
      precondition(next.program == layer.program && next.id == layer.id)
      let copy = StrobeState(layer: next, playing: playing)
      copy.elapsedMicros = elapsedMicros
      copy.lastLogicalStep = lastLogicalStep
      copy.colorIndex = colorIndex
      copy.lastFlashSerial = lastFlashSerial
      copy.signalSessionID = signalSessionID
      copy.flashVisible = flashVisible
      copy.lastFlashStrength = lastFlashStrength
      copy.normalizedMotion = normalizedMotion
      copy.currentColor = currentColor
      copy.animationFrom = animationFrom
      copy.animationTo = animationTo
      copy.animationElapsedMicros = animationElapsedMicros
      copy.animationDurationMicros = animationDurationMicros
      copy.animationFresh = animationFresh
      copy.rotation = rotation
      copy.scale = scale
      copy.frame = frame
      guard next.options != layer.options else { return copy }
      let colors = Self.palette(next)
      copy.colorIndex = ((colorIndex % colors.count) + colors.count) % colors.count
      copy.currentColor = colors[copy.colorIndex]
      if let interval = next.options.intervalMicros,
          interval != layer.options.intervalMicros {
        // Original periodic timers restart their wait, not their on/off state.
        // Comparing absolute elapsed steps across different intervals can move
        // backwards and produce negative palette advances.
        copy.lastLogicalStep = lastLogicalStep % 2
        copy.elapsedMicros = copy.lastLogicalStep * interval
      }
      if next.options.intervalMicros != nil {
        copy.retargetControls(to: copy.currentColor)
        copy.frame = copy.clockFrame()
        return copy
      }
      if program == .backgroundSimpleDisco || program == .backgroundProColorful {
        copy.retargetControls(to: copy.decoratedColor(copy.currentColor))
        return copy
      }
      guard program == .transparentProStrobe else { return copy }

      // Selector/named-mode actions do not call adjustFlashSpeed in Flutter.
      // Re-selecting the identical mode is indistinguishable from an individual
      // value edit in the persistent document; no transient command is invented.
      if next.options.modeIdentity == layer.options.modeIdentity &&
          (next.options.speed != layer.options.speed || next.options.intense != layer.options.intense) {
        copy.flashVisible = false
      }
      copy.retargetControls(to: copy.proFlashFrame())
      return copy
    }

    private func retargetControls(to target: StrobeFrame) {
      if target != animationTo {
        startAnimation(from: frame, to: target)
      } else {
        let duration: Int64 = program == .backgroundSimpleDisco
          ? (layer.options.smooth ? 300_000 : 0) : layer.options.transitionMicros
        if duration != animationDurationMicros {
          let progress = animationDurationMicros == 0 ? 1.0
            : min(1, Double(animationElapsedMicros) / Double(animationDurationMicros))
          animationDurationMicros = duration
          animationElapsedMicros = Int64((progress * Double(duration)).rounded())
          frame = interpolatedFrame()
        }
      }
      // These enclosing transforms are not part of AnimatedContainer's tween.
      frame.rotation = target.rotation
      frame.scale = target.scale
    }

    func advance(by deltaMicros: Int64) -> Bool {
      guard playing, deltaMicros > 0 else { return false }
      let old = frame
      elapsedMicros += deltaMicros
      if let interval = layer.options.intervalMicros {
        let step = elapsedMicros / interval
        if step != lastLogicalStep {
          let advances = ((step + 1) / 2) - ((lastLogicalStep + 1) / 2)
          lastLogicalStep = step
          if advances > 0 {
            let previous = currentColor
            let colors = Self.palette(layer)
            colorIndex = (colorIndex + Int(advances % Int64(colors.count))) % colors.count
            currentColor = colors[colorIndex]
            if layer.options.smooth && step % 2 == 1 {
              startAnimation(from: previous, to: currentColor)
            }
          }
        }
      }
      if animationFresh {
        animationFresh = false
      } else if animationElapsedMicros < animationDurationMicros {
        animationElapsedMicros = min(animationDurationMicros, animationElapsedMicros + deltaMicros)
      }
      if layer.options.intervalMicros != nil {
        frame = clockFrame()
      } else if animationDurationMicros > 0 {
        frame = interpolatedFrame()
      }
      return frame != old
    }

    func consume(_ signal: SceneRenderSignalFrameV2) -> Bool {
      guard playing, layer.program.audioReactive else { return false }
      if layer.program == .transparentProStrobe {
        normalizedMotion = signal.dynamics[3]
      }
      if signal.sessionId != signalSessionID {
        signalSessionID = signal.sessionId
        lastFlashSerial = -1
      }
      guard
            signal.flash.active, signal.flash.serial > lastFlashSerial else {
        return false
      }
      lastFlashSerial = signal.flash.serial
      switch layer.program {
      case .backgroundSimpleDisco, .backgroundProColorful:
        let colors = Self.palette(layer)
        colorIndex = (colorIndex + 1) % colors.count
        rotation += 0.1
        scale = 1 + CGFloat(sin(Double(colorIndex) * 0.1)) * 0.5
        currentColor = colors[colorIndex]
        let target = decoratedColor(currentColor)
        startAnimation(from: frame, to: target)
        // Flutter applies the enclosing transform immediately; only the
        // AnimatedContainer's color/gradient interpolates.
        frame.rotation = target.rotation
        frame.scale = target.scale
      case .transparentProStrobe:
        flashVisible = true
        lastFlashStrength = CGFloat(min(1, max(0, signal.flash.strength)))
        startAnimation(from: frame, to: proFlashFrame())
      default:
        return false
      }
      return true
    }

    func hideTimedFlash() -> Bool {
      guard flashVisible, layer.program == .transparentProStrobe else {
        return false
      }
      flashVisible = false
      startAnimation(from: frame, to: Self.transparent)
      return true
    }

    private func proFlashFrame() -> StrobeFrame {
      guard flashVisible else { return Self.transparent }
      let alpha = layer.options.brightness * lastFlashStrength
      if (layer.options.transparentBlack && normalizedMotion <= 0.2) ||
          (layer.options.transparentWhite && alpha == 1) { return Self.transparent }
      return StrobeFrame(red: 1, green: 1, blue: 1, alpha: alpha)
    }

    private func clockFrame() -> StrobeFrame {
      let on = lastLogicalStep % 2 == 1
      if !on && layer.program == .transparentBlackWhite { return Self.transparent }
      if !on && layer.options.showBlack { return Self.black }
      let color = layer.options.smooth ? interpolatedFrame() : currentColor
      return StrobeFrame(red: color.red, green: color.green, blue: color.blue,
        alpha: layer.options.brightness)
    }

    private func decoratedColor(_ color: StrobeFrame) -> StrobeFrame {
      var result = color
      if layer.options.spark && !layer.options.gradient {
        result = Self.proColors.randomElement()!
      }
      result = StrobeFrame(red: result.red, green: result.green, blue: result.blue,
        alpha: layer.options.gradient ? 1 : layer.options.brightness)
      if layer.options.gradient {
        let colors = Self.palette(layer)
        let end = colors[(colorIndex + 1) % colors.count]
        result.gradientEnd = [end.red, end.green, end.blue, 1]
      }
      result.rotation = layer.options.rotation ? rotation : 0
      result.scale = layer.options.scale ? scale : 1
      return result
    }

    private func startAnimation(from: StrobeFrame, to: StrobeFrame) {
      animationFrom = from
      animationTo = to
      animationElapsedMicros = 0
      animationDurationMicros = layer.program == .backgroundSimpleDisco
        ? (layer.options.smooth ? 300_000 : 0) : layer.options.transitionMicros
      animationFresh = true
      if animationDurationMicros == 0 { frame = to }
    }

    private func interpolatedFrame() -> StrobeFrame {
      let t = animationDurationMicros == 0 ? CGFloat(1)
        : min(1, CGFloat(animationElapsedMicros) / CGFloat(animationDurationMicros))
      func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
      var result = StrobeFrame(
        red: lerp(animationFrom.red, animationTo.red),
        green: lerp(animationFrom.green, animationTo.green),
        blue: lerp(animationFrom.blue, animationTo.blue),
        alpha: lerp(animationFrom.alpha, animationTo.alpha))
      if let start = animationFrom.gradientEnd, let end = animationTo.gradientEnd {
        result.gradientEnd = zip(start, end).map { lerp($0.0, $0.1) }
      } else {
        result.gradientEnd = animationTo.gradientEnd
      }
      result.rotation = animationTo.rotation
      result.scale = animationTo.scale
      return result
    }

    private static func palette(_ layer: StrobeLayer) -> [StrobeFrame] {
      switch layer.program {
      case .backgroundBlackWhite: return blackWhite
      case .backgroundColorLights: return colorLights
      case .backgroundSimpleDisco: return discoColors
      case .backgroundProColorful: return proColors
      case .transparentBlackWhite:
        if layer.options.brightRainbow {
          return rainbow.enumerated().flatMap { index, color in
            index == rainbow.count - 1 ? [color] : [color, white]
          }
        }
        return layer.options.rainbow ? rainbow : [black]
      case .transparentProStrobe: return [white]
      }
    }

    private static let black = StrobeFrame(red: 0, green: 0, blue: 0, alpha: 1)
    private static let red = StrobeFrame(red: 1, green: 0, blue: 0, alpha: 1)
    private static let white = StrobeFrame(red: 1, green: 1, blue: 1, alpha: 1)
    private static let transparent = StrobeFrame(red: 0, green: 0, blue: 0, alpha: 0)
    private static let blackWhite = [black, StrobeFrame(red: 1, green: 1, blue: 1, alpha: 1)]
    private static let colorLights = [
      red,
      StrobeFrame(red: 127.0 / 255.0, green: 1, blue: 0, alpha: 1),
      StrobeFrame(red: 0, green: 1, blue: 1, alpha: 1),
      StrobeFrame(red: 1, green: 0, blue: 1, alpha: 1),
      StrobeFrame(red: 0, green: 1, blue: 0, alpha: 1),
      StrobeFrame(red: 1, green: 0, blue: 1, alpha: 1),
      StrobeFrame(red: 0, green: 0, blue: 1, alpha: 1),
      StrobeFrame(red: 0.8, green: 0.8, blue: 0.8, alpha: 1),
    ]
    private static let discoColors = [
      red,
      StrobeFrame(red: 1, green: 1, blue: 0, alpha: 1),
      StrobeFrame(red: 0, green: 1, blue: 1, alpha: 1),
      StrobeFrame(red: 1, green: 0, blue: 1, alpha: 1),
      StrobeFrame(red: 0, green: 1, blue: 0, alpha: 1),
      StrobeFrame(red: 1, green: 0, blue: 1, alpha: 1),
      StrobeFrame(red: 0, green: 0, blue: 1, alpha: 1),
      StrobeFrame(red: 0.8, green: 0.8, blue: 0.8, alpha: 1),
    ]
    private static func rgb(_ value: UInt32) -> StrobeFrame {
      StrobeFrame(red: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    private static let proColors = [
      rgb(0xF44336), rgb(0x2196F3), rgb(0x4CAF50), rgb(0xFFEB3B),
      rgb(0x00BCD4), rgb(0xE040FB), rgb(0xFF9800), rgb(0x9C27B0),
    ]
    private static let rainbow = [
      rgb(0xF44336), rgb(0xFF9800), rgb(0xFFEB3B), rgb(0x4CAF50),
      rgb(0x2196F3), rgb(0x3F51B5), rgb(0x9C27B0),
    ]
  }

  /// Owns one continuous media source. The published scene buffer remains
  /// authoritative while this object seeks or prerolls, so resource work is
  /// never exposed as a poster/black transition.
  private final class MediaState {
    private(set) var layer: MediaLayer
    private var image: CIImage?
    private var animatedSource: CGImageSource?
    private var animatedFrameEndTimes = [Double]()
    private var animatedDuration = 0.0
    private var animatedFrameIndex = -1
    private var timelineAnchorHostTime = CACurrentMediaTime()
    private var timelineAnchorPtsMicros: Int64
    private var pausedPtsMicros: Int64
    private var playing: Bool
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var videoDurationMicros: Int64?
    private var endObserver: NSObjectProtocol?
    private var decodedVideoFrame = false
    private var invalidated = false
    private let ownerQueue: DispatchQueue
    private let naturalReactiveLightState: SceneRenderV2NaturalReactiveLightState?
    private let rgbGainState: SceneRenderV2RGBGainState?

    var id: String { layer.id }
    var resourceIdentity: String { layer.resourceIdentity }
    var decoderCount: Int { layer.kind.isVideo ? 1 : 0 }
    var hasCompleteFrame: Bool { image != nil }

    init(
      layer: MediaLayer,
      mediaPtsMicros: Int64,
      ownerQueue: DispatchQueue
    ) throws {
      self.layer = layer
      self.ownerQueue = ownerQueue
      self.timelineAnchorPtsMicros = mediaPtsMicros
      self.pausedPtsMicros = mediaPtsMicros
      // A new decoder remains paused through seek, preroll, and the atomic
      // first-frame render. The owning session starts it only after commit.
      self.playing = false
      naturalReactiveLightState = layer.naturalReactiveLight.map {
        SceneRenderV2NaturalReactiveLightState(config: $0)
      }
      rgbGainState = layer.rgbGain.map {
        SceneRenderV2RGBGainState(config: $0)
      }
      if layer.kind == .animatedImage {
        guard loadAnimatedImage() else {
          throw RuntimeError("animated_image_decode_failed")
        }
      } else {
        guard configureVideo() else {
          throw RuntimeError("video_configuration_failed")
        }
      }
    }

    func canReuse(for next: MediaLayer) -> Bool {
      layer.id == next.id &&
        layer.kind == next.kind &&
        layer.resourceIdentity == next.resourceIdentity &&
        abs(layer.playbackRate - next.playbackRate) < 0.000_001 &&
        layer.naturalReactiveLight == next.naturalReactiveLight &&
        layer.rgbGain == next.rgbGain
    }

    func rebind(_ next: MediaLayer) {
      precondition(canReuse(for: next))
      layer = next
    }

    func prepareInitialFrame(
      deadline: DispatchTime,
      onWait: () -> Void,
      shouldContinue: () -> Bool
    ) -> Bool {
      guard layer.kind.isVideo else { return image != nil }
      guard let player, let item = player.currentItem, let output else {
        return false
      }
      guard shouldContinue() else { return false }
      let targetPtsMicros = sceneRenderV2LoopPhaseMicros(
        mediaPtsMicros: timelineAnchorPtsMicros,
        durationMicros: videoDurationMicros
      )
      pausedPtsMicros = targetPtsMicros
      timelineAnchorPtsMicros = targetPtsMicros
      let target = CMTime(
        value: targetPtsMicros,
        timescale: 1_000_000
      )

      player.pause()
      player.cancelPendingPrerolls()
      item.cancelPendingSeeks()
      output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)

      guard waitUntilReadyForPreroll(
        player: player,
        item: item,
        deadline: deadline,
        onWait: onWait,
        shouldContinue: shouldContinue
      ) else {
        cancelInitialFramePreparation(player: player, item: item)
        return false
      }

      let seek = SceneRenderV2PrerollCompletion()
      player.seek(
        to: target,
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { finished in
        seek.complete(finished)
      }
      guard seek.wait(
        until: deadline,
        onWait: onWait,
        shouldContinue: shouldContinue
      ) else {
        cancelInitialFramePreparation(player: player, item: item)
        return false
      }

      guard shouldContinue() else {
        cancelInitialFramePreparation(player: player, item: item)
        return false
      }

      guard waitUntilReadyForPreroll(
        player: player,
        item: item,
        deadline: deadline,
        onWait: onWait,
        shouldContinue: shouldContinue
      ) else {
        cancelInitialFramePreparation(player: player, item: item)
        return false
      }

      guard sceneRenderV2CanInvokePreroll(
        preparationCurrent: shouldContinue(),
        playerIsCurrent: self.player === player,
        itemIsCurrent: player.currentItem === item,
        playerRate: player.rate,
        playerStatus: player.status,
        itemStatus: item.status
      ) else {
        cancelInitialFramePreparation(player: player, item: item)
        return false
      }

      let preroll = SceneRenderV2PrerollCompletion()
      player.preroll(atRate: layer.playbackRate) { finished in
        preroll.complete(finished)
      }
      guard preroll.wait(
        until: deadline,
        onWait: onWait,
        shouldContinue: shouldContinue
      ) else {
        cancelInitialFramePreparation(player: player, item: item)
        return false
      }

      while DispatchTime.now() < deadline {
        guard shouldContinue() else {
          cancelInitialFramePreparation(player: player, item: item)
          return false
        }
        if prepareVideoFrame(output: output, itemTime: target) ||
            prepareVideoFrame(output: output, itemTime: player.currentTime()) {
          player.pause()
          return true
        }
        if item.status == .failed { break }
        onWait()
        Thread.sleep(forTimeInterval: 0.005)
      }
      cancelInitialFramePreparation(player: player, item: item)
      return false
    }

    func prepareFrame(hostTime: CFTimeInterval) -> Bool {
      guard playing else { return false }
      switch layer.kind {
      case .animatedImage:
        return prepareAnimatedFrame(hostTime: hostTime)
      case .video, .straightAlphaVideo, .packedAlphaVideo:
        guard let output else { return false }
        return prepareVideoFrame(output: output, hostTime: hostTime)
      }
    }

    func currentImage() -> CIImage? {
      guard let image else { return nil }
      guard let normalized = normalizedSceneLayerAlpha(
        image,
        mode: layer.kind.alphaMode
      ) else {
        return nil
      }
      let gainAdjusted = rgbGainState?.apply(to: normalized) ?? normalized
      return naturalReactiveLightState?.apply(to: gainAdjusted) ?? gainAdjusted
    }

    func consume(_ frame: SceneRenderSignalFrameV2) -> Bool {
      let naturalChanged = naturalReactiveLightState?.consume(frame) ?? false
      let gainChanged = rgbGainState?.consume(frame) ?? false
      return naturalChanged || gainChanged
    }

    func setPlaying(_ next: Bool, hostTime: CFTimeInterval) {
      guard next != playing else { return }
      if next {
        timelineAnchorHostTime = hostTime
        timelineAnchorPtsMicros = pausedPtsMicros
        playing = true
        player?.playImmediately(atRate: layer.playbackRate)
      } else {
        pausedPtsMicros = currentPtsMicros(hostTime: hostTime)
        playing = false
        player?.pause()
      }
    }

    func tearDown() {
      invalidated = true
      playing = false
      player?.pause()
      player?.cancelPendingPrerolls()
      player?.currentItem?.cancelPendingSeeks()
      if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
      endObserver = nil
      output = nil
      player = nil
      animatedSource = nil
      animatedFrameEndTimes.removeAll(keepingCapacity: false)
      image = nil
    }

    private func currentPtsMicros(hostTime: CFTimeInterval) -> Int64 {
      if let player {
        let seconds = CMTimeGetSeconds(player.currentTime())
        if seconds.isFinite && seconds >= 0 {
          return Int64((seconds * 1_000_000).rounded())
        }
      }
      guard playing else { return pausedPtsMicros }
      let delta = max(0, hostTime - timelineAnchorHostTime)
      return timelineAnchorPtsMicros +
        Int64((delta * Double(layer.playbackRate) * 1_000_000).rounded())
    }

    private func loadAnimatedImage() -> Bool {
      let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
      guard
        let source = CGImageSourceCreateWithURL(
          layer.url as CFURL,
          options as CFDictionary
        ),
        CGImageSourceGetCount(source) > 0,
        CGImageSourceGetCount(source) <= 600
      else { return false }
      var elapsed = 0.0
      for index in 0..<CGImageSourceGetCount(source) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
          as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary]
          as? [CFString: Any]
        let unclamped = (gif?[kCGImagePropertyGIFUnclampedDelayTime]
          as? NSNumber)?.doubleValue
        let clamped = (gif?[kCGImagePropertyGIFDelayTime]
          as? NSNumber)?.doubleValue
        elapsed += max(unclamped ?? clamped ?? 0.1, 0.02)
        animatedFrameEndTimes.append(elapsed)
      }
      guard elapsed > 0 else { return false }
      animatedDuration = elapsed
      animatedSource = source
      timelineAnchorHostTime = CACurrentMediaTime()
      return decodeAnimatedFrame(at: frameIndex(forPtsMicros: timelineAnchorPtsMicros))
    }

    private func frameIndex(forPtsMicros ptsMicros: Int64) -> Int {
      guard animatedDuration > 0 else { return 0 }
      let seconds = (Double(max(0, ptsMicros)) / 1_000_000)
        .truncatingRemainder(dividingBy: animatedDuration)
      return animatedFrameEndTimes.firstIndex(where: { seconds < $0 }) ??
        max(0, animatedFrameEndTimes.count - 1)
    }

    private func prepareAnimatedFrame(hostTime: CFTimeInterval) -> Bool {
      let next = frameIndex(forPtsMicros: currentPtsMicros(hostTime: hostTime))
      guard next != animatedFrameIndex else { return false }
      return decodeAnimatedFrame(at: next)
    }

    private func decodeAnimatedFrame(at index: Int) -> Bool {
      guard let animatedSource, index >= 0,
            index < CGImageSourceGetCount(animatedSource) else { return false }
      let options: [CFString: Any] = [
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 4096,
      ]
      guard let frame = CGImageSourceCreateThumbnailAtIndex(
        animatedSource,
        index,
        options as CFDictionary
      ) else { return false }
      image = CIImage(cgImage: frame)
      animatedFrameIndex = index
      return true
    }

    private func configureVideo() -> Bool {
      let asset = AVURLAsset(url: layer.url)
      guard let track = asset.tracks(withMediaType: .video).first else { return false }
      let durationSeconds = CMTimeGetSeconds(asset.duration)
      let durationMicros = durationSeconds * 1_000_000
      if durationSeconds.isFinite,
         durationSeconds > 0,
         durationMicros <= Double(Int64.max) {
        videoDurationMicros = Int64(durationMicros.rounded(.down))
      }
      let descriptions = track.formatDescriptions.compactMap { raw -> CMFormatDescription? in
        guard CFGetTypeID(raw as CFTypeRef) == CMFormatDescriptionGetTypeID() else {
          return nil
        }
        return (raw as! CMFormatDescription)
      }
      let pixelFormat = sceneSurfaceVideoOutputPixelFormat(
        alphaMode: layer.kind.alphaMode,
        codecTypes: descriptions.map(CMFormatDescriptionGetMediaSubType),
        encodedWidths: descriptions.map {
          CMVideoFormatDescriptionGetDimensions($0).width
        },
        fullRangeVideoExtensions: descriptions.map { description in
          let extensions = CMFormatDescriptionGetExtensions(description) as NSDictionary?
          return extensions?[kCMFormatDescriptionExtension_FullRangeVideo]
        }
      )
      let item = AVPlayerItem(asset: asset)
      let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
        kCVPixelBufferMetalCompatibilityKey as String: true,
      ])
      item.add(output)
      let player = AVPlayer(playerItem: item)
      player.actionAtItemEnd = .none
      player.automaticallyWaitsToMinimizeStalling = false
      player.isMuted = true
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: nil
      ) { [weak self, weak player] _ in
        guard let self, let player else { return }
        self.ownerQueue.async { [weak self, weak player] in
          guard
            let self,
            let player,
            sceneRenderV2ShouldRestartMediaLoop(
              playing: self.playing,
              playerIsCurrent: self.player === player,
              invalidated: self.invalidated
            )
          else { return }
          player.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
          ) { [weak self, weak player] finished in
            guard finished, let self, let player else { return }
            self.ownerQueue.async { [weak self, weak player] in
              guard
                let self,
                let player,
                sceneRenderV2ShouldRestartMediaLoop(
                  playing: self.playing,
                  playerIsCurrent: self.player === player,
                  invalidated: self.invalidated
                )
              else { return }
              player.playImmediately(atRate: self.layer.playbackRate)
            }
          }
        }
      }
      self.output = output
      self.player = player
      return true
    }

    private func prepareVideoFrame(
      output: AVPlayerItemVideoOutput,
      hostTime: CFTimeInterval
    ) -> Bool {
      let itemTime = output.itemTime(forHostTime: hostTime)
      return prepareVideoFrame(output: output, itemTime: itemTime)
    }

    private func prepareVideoFrame(
      output: AVPlayerItemVideoOutput,
      itemTime: CMTime
    ) -> Bool {
      guard output.hasNewPixelBuffer(forItemTime: itemTime),
            let buffer = output.copyPixelBuffer(
              forItemTime: itemTime,
              itemTimeForDisplay: nil
            ) else { return false }
      prepareSceneVideoPixelBufferForAlphaMode(buffer, alphaMode: layer.kind.alphaMode)
      image = CIImage(cvPixelBuffer: buffer)
      decodedVideoFrame = true
      return true
    }

    private func cancelInitialFramePreparation(
      player: AVPlayer,
      item: AVPlayerItem
    ) {
      player.cancelPendingPrerolls()
      item.cancelPendingSeeks()
      player.pause()
    }

    private func waitUntilReadyForPreroll(
      player: AVPlayer,
      item: AVPlayerItem,
      deadline: DispatchTime,
      onWait: () -> Void,
      shouldContinue: () -> Bool
    ) -> Bool {
      while DispatchTime.now() < deadline {
        guard shouldContinue() else { return false }
        switch sceneRenderV2PrerollReadiness(
          playerStatus: player.status,
          itemStatus: item.status
        ) {
        case .ready:
          return true
        case .failed:
          return false
        case .waiting:
          onWait()
          Thread.sleep(forTimeInterval: 0.005)
        }
      }
      return false
    }
  }

  private let textureRegistry: FlutterTextureRegistry
  private let renderEngine: MusicVibeRenderEngine?
  private let metalContext: SceneSurfaceMetalContext?
  private var graphics: GraphicsResources?
  private let graphicsResourceFactory: GraphicsResourceFactory
  private static let outputColorSpace = CGColorSpaceCreateDeviceRGB()
  private static let radialProfileKernel = CIKernel(source: """
    kernel vec4 sceneRadialProfileV1(
      sampler profile,
      vec2 targetOrigin,
      vec2 targetSize,
      float profileRow,
      float radiusScale,
      float luminanceScale
    ) {
      vec2 point = destCoord() - targetOrigin;
      vec2 center = targetSize * 0.5;
      float coverScale = max(targetSize.x / 720.0, targetSize.y / 1280.0);
      float radius = max(733.75 * coverScale * radiusScale, 0.0001);
      float radialIndex = clamp(length(point - center) / radius, 0.0, 1.0) * 733.0;
      vec2 profileCoordinate = samplerTransform(
        profile,
        vec2(radialIndex + 0.5, profileRow + 0.5)
      );
      vec4 color = sample(profile, profileCoordinate);
      return vec4(color.rgb * luminanceScale, color.a);
    }
  """)
  private static let magicMoonAuraKernel = CIColorKernel(source: """
    kernel vec4 sceneMagicMoonAuraV1(
      vec2 targetOrigin,
      vec2 center,
      float radius,
      float opacity
    ) {
      float d = distance(destCoord(), center);
      float broad = d / max(radius * 3.8, 0.0001);
      vec4 broadColor;
      if (broad <= 0.28) {
        broadColor = mix(vec4(0x71/255.0,0x83/255.0,0xad/255.0,0x10/255.0),
          vec4(0x5e/255.0,0x71/255.0,0x99/255.0,0x07/255.0), broad/0.28);
      } else if (broad <= 0.62) {
        broadColor = mix(vec4(0x5e/255.0,0x71/255.0,0x99/255.0,0x07/255.0),
          vec4(0x52/255.0,0x64/255.0,0x8d/255.0,0x02/255.0),
          (broad-0.28)/0.34);
      } else {
        broadColor = mix(vec4(0x52/255.0,0x64/255.0,0x8d/255.0,0x02/255.0),
          vec4(0x52/255.0,0x64/255.0,0x8d/255.0,0.0),
          clamp((broad-0.62)/0.38,0.0,1.0));
      }
      broadColor *= step(broad, 1.0);

      float rim = d / max(radius * 1.65, 0.0001);
      vec4 rimColor = vec4(0.0);
      if (rim > 0.50 && rim <= 0.58) {
        rimColor = mix(vec4(0.0), vec4(0xc9/255.0,0xd8/255.0,0xf7/255.0,0x28/255.0),
          (rim-0.50)/0.08);
      } else if (rim <= 0.74 && rim > 0.58) {
        rimColor = mix(vec4(0xc9/255.0,0xd8/255.0,0xf7/255.0,0x28/255.0),
          vec4(0x9f/255.0,0xb4/255.0,0xde/255.0,0x0c/255.0),
          (rim-0.58)/0.16);
      } else if (rim <= 1.0 && rim > 0.74) {
        rimColor = mix(vec4(0x9f/255.0,0xb4/255.0,0xde/255.0,0x0c/255.0),
          vec4(0x9f/255.0,0xb4/255.0,0xde/255.0,0.0),
          (rim-0.74)/0.26);
      }
      broadColor.a *= opacity;
      rimColor.a *= opacity;
      vec3 broadPremul = broadColor.rgb * broadColor.a;
      vec3 rimPremul = rimColor.rgb * rimColor.a;
      float alpha = rimColor.a + broadColor.a * (1.0-rimColor.a);
      vec3 rgb = rimPremul + broadPremul * (1.0-rimColor.a);
      return vec4(rgb, alpha);
    }
  """)
  private static let radiantEmissionKernel = CIColorKernel(source: """
    float radiantGaussian(float value, float center, float width) {
      float offset = (value - center) / max(width, 0.0001);
      return exp(-offset * offset);
    }
    float radiantEaseOutCubic(float value) {
      float inverseValue = 1.0 - clamp(value, 0.0, 1.0);
      return 1.0 - inverseValue * inverseValue * inverseValue;
    }
    vec2 radiantPulse(
      float distanceToCenter,
      float angle,
      float progress,
      float strength,
      float motionScale
    ) {
      if (strength <= 0.0001 || progress >= 1.0) return vec2(0.0);
      float eased = radiantEaseOutCubic(progress);
      float animatedRadius = mix(0.015, 1.05, eased);
      float radius = mix(0.16, animatedRadius, motionScale);
      float decay = pow(1.0 - progress, 0.72) * strength;
      float width = mix(0.045, 0.105, eased);
      float front = radiantGaussian(distanceToCenter, radius, width) * decay;
      float interior = 1.0 - smoothstep(radius * 0.42, radius, distanceToCenter);
      interior *= smoothstep(0.015, 0.16, distanceToCenter) * decay * 0.20;
      float rayPattern = 0.5 + 0.5 * sin(angle * 12.0 + eased * 2.4);
      rayPattern *= 0.62 + 0.38 * sin(angle * 23.0 - eased * 1.7);
      rayPattern = smoothstep(0.30, 0.92, rayPattern);
      float rays = rayPattern * interior * (0.20 + 0.80 * motionScale);
      return vec2(front + interior, rays);
    }
    kernel vec4 sceneRadiantEmissionV1(
      vec2 targetOrigin,
      vec2 targetSize,
      vec2 center,
      float flowValue,
      float bassValue,
      float pulseAProgress,
      float pulseAStrength,
      float pulseBProgress,
      float pulseBStrength,
      float intensityScale,
      float opacity,
      float motionScale
    ) {
      vec2 safeSize = max(targetSize, vec2(1.0));
      vec2 uv = (destCoord() - targetOrigin) / safeSize;
      uv.y = 1.0 - uv.y;
      vec2 delta = uv - center;
      delta.x *= safeSize.x / safeSize.y;
      float distanceToCenter = length(delta);
      float angle = atan(delta.y, delta.x);
      float flow = clamp(flowValue, 0.0, 1.0);
      float bass = clamp(bassValue, 0.0, 1.0);
      float coreDrive = flow * 0.42 + bass * 0.62;
      float core = radiantGaussian(distanceToCenter, 0.0, 0.12 + bass * 0.025);
      core *= coreDrive;
      vec2 pulseA = radiantPulse(
        distanceToCenter, angle, pulseAProgress, pulseAStrength, motionScale
      );
      vec2 pulseB = radiantPulse(
        distanceToCenter, angle, pulseBProgress, pulseBStrength, motionScale
      );
      float wave = pulseA.x + pulseB.x;
      float rays = pulseA.y + pulseB.y;
      float energy = (core * 0.62 + wave * 0.78 + rays * 0.62) * intensityScale;
      float colorPosition = clamp(distanceToCenter / 0.78, 0.0, 1.0);
      vec3 innerColor = vec3(1.0, 0.902, 0.541);
      vec3 middleColor = vec3(0.333, 0.91, 1.0);
      vec3 outerColor = vec3(1.0, 0.333, 0.847);
      vec3 color = mix(
        innerColor, middleColor, smoothstep(0.08, 0.48, colorPosition)
      );
      color = mix(color, outerColor, smoothstep(0.46, 0.92, colorPosition));
      color += innerColor * core * 0.18;
      float alpha = min(energy, 0.52) * opacity;
      return vec4(color * alpha, alpha);
    }
  """)
  private static let rainbowWaterfallKernel = CIColorKernel(source: """
    vec3 rainbowHsvToRgb(vec3 hsv) {
      vec3 p = abs(fract(hsv.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
      vec3 rgb = clamp(p - 1.0, 0.0, 1.0);
      rgb = rgb * rgb * (3.0 - 2.0 * rgb);
      return hsv.z * mix(vec3(1.0), rgb, hsv.y);
    }
    float rainbowTriangleWave(float value) {
      const float kTau = 6.28318530717958647692;
      return abs(fract(value / kTau) * 2.0 - 1.0) * 2.0 - 1.0;
    }
    kernel vec4 sceneRainbowWaterfallV1(
      vec2 targetOrigin,
      vec2 targetSize,
      float phaseValue,
      float bassValue,
      float bodyValue,
      float pulseValue,
      float energyValue,
      float flowValue,
      float opacity,
      float reactionScale
    ) {
      vec2 safeSize = max(targetSize, vec2(1.0));
      vec2 uv = (destCoord() - targetOrigin) / safeSize;
      uv.y = 1.0 - uv.y;
      vec2 pixelPoint = uv * safeSize;
      vec2 position = (pixelPoint - safeSize * 0.5) / safeSize.x;
      float radius = length(position);
      float angle = atan(position.y, position.x);
      float impulseScale = (bassValue * 0.025 + pulseValue * 0.052) * reactionScale;
      float coreRadius = 0.0148;
      float logarithmicRadius = log2(
        max(radius * exp(-impulseScale), coreRadius) / coreRadius
      );
      float radialCycle = logarithmicRadius * 0.985 - phaseValue;
      float teeth = rainbowTriangleWave(
        angle * 17.0 + logarithmicRadius * 1.14 + 0.31
      ) * 0.158;
      teeth += rainbowTriangleWave(
        angle * 29.0 - logarithmicRadius * 2.07 - 0.83
      ) * 0.086;
      teeth += rainbowTriangleWave(
        angle * 47.0 + logarithmicRadius * 4.18 + 1.37
      ) * 0.046;
      teeth += sin(angle * 83.0 - logarithmicRadius * 6.82 - 0.46) * 0.021;
      teeth *= 1.0 + bodyValue * 0.035 * reactionScale;
      float hue = fract(radialCycle + teeth + 0.286);
      float saturation = clamp(0.965 + bodyValue * 0.015 * reactionScale, 0.0, 1.0);
      float value = clamp(
        0.985 + (energyValue * 0.025 + pulseValue * 0.012) * reactionScale, 0.0, 1.0
      );
      vec3 color = rainbowHsvToRgb(vec3(hue, saturation, value));
      float core = 1.0 - smoothstep(
        coreRadius * 0.97, coreRadius * 1.03, radius
      );
      float coreBorderOuter = 1.0 - smoothstep(
        coreRadius * 1.24, coreRadius * 1.34, radius
      );
      float coreBorder = clamp(coreBorderOuter - core, 0.0, 1.0);
      color = mix(color, vec3(0.075, 0.035, 0.16), coreBorder * 0.94);
      color = mix(color, vec3(0.56, 0.995, 0.67), core);
      color = mix(color, vec3(1.0), 0.012 + flowValue * 0.006);
      color = pow(clamp(color, 0.0, 1.0), vec3(0.96));
      float alpha = clamp(opacity, 0.0, 1.0);
      return vec4(color * alpha, alpha);
    }
  """)
  private static let filterGradeKernel = CIColorKernel(source: """
    float gradeLuma(vec3 value) {
      return dot(value, vec3(0.2126, 0.7152, 0.0722));
    }
    vec3 gradeSrgbToLinear(vec3 value) {
      vec3 low = value / 12.92;
      vec3 high = pow((value + 0.055) / 1.055, vec3(2.4));
      return mix(low, high, step(vec3(0.04045), value));
    }
    vec3 gradeLinearToSrgb(vec3 value) {
      value = max(value, vec3(0.0));
      vec3 low = value * 12.92;
      vec3 high = 1.055 * pow(value, vec3(1.0 / 2.4)) - 0.055;
      return mix(low, high, step(vec3(0.0031308), value));
    }
    vec3 gradeMatchLuma(vec3 color, float target) {
      return color * (target / max(gradeLuma(color), 0.0001));
    }
    vec3 gradeLumaMatchedTint(vec3 tint, float target) {
      return tint * (target / max(gradeLuma(tint), 0.001));
    }
    vec3 gradeSelectivePresence(
      vec3 color,
      float cyanPresence,
      float magentaPresence,
      float goldPresence
    ) {
      float base = max(gradeLuma(color), 0.0);
      float high = max(color.r, max(color.g, color.b));
      float low = min(color.r, min(color.g, color.b));
      float chroma = max(high - low, 0.0);
      float strength = smoothstep(0.012, 0.28, chroma);
      float inverseChroma = 1.0 / max(chroma, 0.0001);
      float cyan = max(min(color.g, color.b) - color.r, 0.0) * inverseChroma;
      float magenta = max(min(color.r, color.b) - color.g, 0.0) * inverseChroma;
      float gold = max(min(color.r, color.g) - color.b, 0.0) * inverseChroma;
      float presence =
        cyanPresence * strength * smoothstep(0.04, 0.72, cyan) +
        magentaPresence * strength * smoothstep(0.04, 0.72, magenta) +
        goldPresence * strength * smoothstep(0.04, 0.72, gold);
      float scale = clamp(1.0 + presence * 0.72, 0.25, 1.85);
      vec3 adjusted = max(mix(vec3(base), color, scale), vec3(0.0));
      return gradeMatchLuma(
        adjusted,
        max(base * (1.0 + presence * 0.045), 0.0)
      );
    }
    kernel vec4 sceneFilterGradeV2(
      __sample sourceSample,
      vec2 origin,
      vec2 size,
      float intensity,
      float exposure,
      float contrast,
      float saturation,
      float vibrance,
      float temperature,
      float tint,
      float blackLift,
      float highlightRolloff,
      float shadowDepth,
      float midtoneBalance,
      float colorDensity,
      float cyanPresence,
      float magentaPresence,
      float goldPresence,
      vec3 shadowTint,
      float shadowAmount,
      vec3 midtoneTint,
      float midtoneAmount,
      vec3 highlightTint,
      float highlightAmount,
      float vignette,
      float vignetteSoftness
    ) {
      if (sourceSample.a <= 0.0001) {
        return sourceSample;
      }
      vec3 sourceSrgb = clamp(sourceSample.rgb / sourceSample.a, 0.0, 1.0);
      vec3 source = gradeSrgbToLinear(sourceSrgb);
      vec3 color = source * exp2(exposure);
      float baseLuma = max(gradeLuma(color), 0.0);
      float shadowMask = 1.0 - smoothstep(0.04, 0.46, baseLuma);
      color = max(color + vec3(blackLift * shadowMask), vec3(0.0));
      float liftedLuma = max(gradeLuma(color), 0.0);
      float depthMask = 1.0 - smoothstep(0.035, 0.42, liftedLuma);
      color *= 1.0 - shadowDepth * depthMask * 0.42;
      color = max((color - vec3(0.18)) * contrast + vec3(0.18), vec3(0.0));
      float currentLuma = max(gradeLuma(color), 0.0);
      float midMask = smoothstep(0.025, 0.22, currentLuma) *
        (1.0 - smoothstep(0.58, 1.04, currentLuma));
      color = gradeMatchLuma(
        color,
        max(currentLuma + midtoneBalance * midMask * 0.16, 0.0)
      );
      color *= max(vec3(
        1.0 + temperature * 0.24 + tint * 0.055,
        1.0 - tint * 0.10,
        1.0 - temperature * 0.24 + tint * 0.055
      ), vec3(0.5));
      currentLuma = max(gradeLuma(color), 0.0);
      color = mix(vec3(currentLuma), color, saturation);
      float chroma = clamp(
        max(color.r, max(color.g, color.b)) -
          min(color.r, min(color.g, color.b)),
        0.0,
        1.0
      );
      float vibranceScale = max(
        0.0,
        1.0 + vibrance * (1.0 - smoothstep(0.04, 0.48, chroma))
      );
      color = max(mix(vec3(currentLuma), color, vibranceScale), vec3(0.0));
      currentLuma = max(gradeLuma(color), 0.0);
      float densityMask = smoothstep(0.025, 0.20, currentLuma) *
        (1.0 - smoothstep(0.64, 1.08, currentLuma));
      float densityScale = clamp(
        1.0 + colorDensity * densityMask * (1.0 - chroma * 0.45) * 0.85,
        0.2,
        1.9
      );
      color = max(mix(vec3(currentLuma), color, densityScale), vec3(0.0));
      color = gradeSelectivePresence(
        color,
        cyanPresence,
        magentaPresence,
        goldPresence
      );
      currentLuma = max(gradeLuma(color), 0.0);
      float shadows = 1.0 - smoothstep(0.08, 0.43, currentLuma);
      float highlights = smoothstep(0.48, 0.92, currentLuma);
      float midtones = clamp(1.0 - max(shadows, highlights), 0.0, 1.0);
      color = mix(
        color,
        gradeLumaMatchedTint(shadowTint, currentLuma),
        shadows * shadowAmount
      );
      color = mix(
        color,
        gradeLumaMatchedTint(midtoneTint, currentLuma),
        midtones * midtoneAmount
      );
      color = mix(
        color,
        gradeLumaMatchedTint(highlightTint, currentLuma),
        highlights * highlightAmount
      );
      float highlightLuma = max(gradeLuma(color), 0.0);
      float excess = max(highlightLuma - 0.52, 0.0);
      float compressed = 0.52 + excess /
        (1.0 + excess * (1.5 + 2.5 * highlightRolloff));
      float shoulder = smoothstep(0.52, 1.05, highlightLuma) *
        highlightRolloff;
      color = gradeMatchLuma(
        color,
        mix(highlightLuma, compressed, shoulder)
      );
      vec2 uv = (destCoord() - origin) / size;
      vec2 centered = (uv - 0.5) * size / min(size.x, size.y);
      float start = mix(0.48, 0.78, vignetteSoftness);
      float mask = smoothstep(start, start + 0.42, length(centered));
      color *= 1.0 - vignette * mask * 0.58;
      vec3 result = mix(source, max(color, vec3(0.0)), clamp(intensity, 0.0, 1.0));
      return vec4(
        clamp(gradeLinearToSrgb(result), 0.0, 1.0) * sourceSample.a,
        sourceSample.a
      );
    }
    """)
  private let queue = DispatchQueue(
    label: "com.chic.colorlights.scene-surface-v2.image",
    qos: .userInteractive
  )
  private static let qaLogQueue = DispatchQueue(
    label: "com.chic.colorlights.scene-surface-v2.qa-log",
    qos: .utility
  )
  private var sessions = [String: Session]()
  private let maximumPresentationFramesPerSecond: Int
  private var applicationActive: Bool
  private let applicationActivitySignal: SceneRenderV2ApplicationActivitySignal
  private let preparationGeneration = SceneRenderV2PreparationGeneration()

  init(
    textureRegistry: FlutterTextureRegistry,
    device: MTLDevice?,
    ciContext: CIContext,
    renderEngine: MusicVibeRenderEngine? = nil,
    metalContext: SceneSurfaceMetalContext? = nil,
    graphicsResourceFactory: GraphicsResourceFactory? = nil,
    maximumPresentationFramesPerSecond: Int = UIScreen.main.maximumFramesPerSecond,
    applicationActive: Bool = true
  ) {
    self.textureRegistry = textureRegistry
    self.renderEngine = renderEngine
    self.metalContext = metalContext
    self.maximumPresentationFramesPerSecond = max(
      1,
      maximumPresentationFramesPerSecond
    )
    self.applicationActive = applicationActive
    self.applicationActivitySignal = SceneRenderV2ApplicationActivitySignal(
      active: applicationActive
    )
    self.graphics = device.map {
      GraphicsResources(device: $0, ciContext: ciContext)
    }
    self.graphicsResourceFactory = graphicsResourceFactory ?? {
      guard let replacementDevice = MTLCreateSystemDefaultDevice() else {
        return nil
      }
      return (
        replacementDevice,
        CIContext(
          mtlDevice: replacementDevice,
          options: [.cacheIntermediates: false]
        )
      )
    }
  }

  func preflight(arguments: Any?) -> [String: Any]? {
    guard
      graphics != nil,
      let arguments = arguments as? [String: Any],
      Set(arguments.keys) == Set([
        "sceneDocumentV2", "semanticPlanHash", "registryRevision",
      ]),
      let document = arguments["sceneDocumentV2"] as? [String: Any],
      let semanticPlanHash = arguments["semanticPlanHash"] as? String,
      let registryRevision = arguments["registryRevision"] as? String,
      registryRevision == SceneRenderNodeRegistryV1Generated.revision,
      let shadow = SceneRenderV2ShadowCompiler.preflight(
        arguments: arguments,
        metalAvailable: true
      ),
      shadow.issueCodes == ["v2_runtime_not_installed"],
      SceneRenderV2ShadowCompiler.semanticPlanHash(document: document) ==
        semanticPlanHash,
      let materialized = Self.materializeResources(document, resolvedPaths: nil),
      Self.parseDocument(materialized, loadImage: false) != nil,
      Self.qualityHashes(document) != nil
    else {
      return nil
    }
    return [
      "supported": true,
      "semanticPlanHash": semanticPlanHash,
      "registryRevision": registryRevision,
      "capabilityClass": capabilityClass,
      "supportedQualityLevels": Self.qualityLevels,
      "issueCodes": [String](),
    ]
  }

  func attach(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let device = graphics?.device,
      let requestedPlan = parseAttach(arguments)
    else {
      result(error("attach_v2_invalid", "Invalid V2 graph session."))
      return
    }
    let texture = Texture()
    let textureID = textureRegistry.register(texture)
    guard textureID >= 0 else {
      result(error("attach_v2_texture_failed", "Unable to register V2 texture."))
      return
    }
    let preparationTicket = preparationGeneration.begin()
    queue.async { [weak self] in
      guard let self else { return }
      let preparationShouldContinue = { [weak self] in
        guard let self else { return false }
        return self.preparationGeneration.isCurrent(preparationTicket) &&
          self.applicationActivitySignal.active
      }
      self.applyLatestApplicationActivity()
      var plan = requestedPlan
      plan.playing = SceneRenderV2PlaybackGate.effectivePlayback(
        requestedForegroundPlaying: requestedPlan.playing,
        applicationActive: self.applicationActive,
        pictureInPictureRetained: false,
        pictureInPicturePlaying: false
      )
      guard self.sessions[plan.sessionID] == nil else {
        DispatchQueue.main.async {
          self.textureRegistry.unregisterTexture(textureID)
          result(self.error("attach_v2_session_exists", "V2 session already exists."))
        }
        return
      }
      var candidateMediaStates = [String: MediaState]()
      var candidateInstalledProgramStates =
        [String: SceneRenderV2InstalledProgramState]()
      var candidateSession: Session?
      do {
        let mediaStates = try self.makeMediaStates(
          plan: plan,
          liveStatesForBudget: self.liveMediaStatesForDecoderBudget()
        )
        candidateMediaStates = mediaStates
        guard self.prepareInitialMedia(
          mediaStates,
          shouldContinue: preparationShouldContinue
        ) else {
          throw RuntimeError("media_preroll_timeout")
        }
        self.applyLatestApplicationActivity()
        guard preparationShouldContinue() else {
          throw RuntimeError("media_preroll_cancelled")
        }
        // A candidate graph is rendered and published while paused. The
        // foreground/PiP intent becomes authoritative only after publication.
        plan.playing = false
        guard let installedProgramStates = self.makeInstalledProgramStates(
          plan: plan
        ) else {
          throw RuntimeError("installed_program_initialization_failed")
        }
        candidateInstalledProgramStates = installedProgramStates
        let session = Session(
          texture: texture,
          textureID: textureID,
          plan: plan,
          mediaStates: mediaStates,
          installedProgramStates: installedProgramStates
        )
        candidateSession = session
        session.foregroundPlaying = requestedPlan.playing
        let buffer = try self.renderFrame(
          session: session,
          plan: plan,
          device: device,
          strobeFrames: self.strobeFrames(session)
        )
        guard session.mediaCommitGate.markRendered() else {
          throw RuntimeError("media_commit_state_invalid")
        }
        self.beginSteadyStateMetrics(session)
        DispatchQueue.main.async {
          let published = self.preparationGeneration.commitIfCurrent(
            preparationTicket
          ) {
            session.mediaCommitGate.commitPublication {
              texture.publish(buffer)
              self.textureRegistry.textureFrameAvailable(textureID)
            }
          }
          // This finite transaction owns the candidate until registration or
          // cancellation. The texture registry does not retain its Session.
          self.queue.async { [self, session] in
            guard
              published,
              self.preparationGeneration.isCurrent(preparationTicket),
              self.sessions[plan.sessionID] == nil
            else {
              session.mediaCommitGate.invalidate()
              session.mediaStates.values.forEach { $0.tearDown() }
              session.installedProgramStates.values.forEach { $0.tearDown() }
              DispatchQueue.main.async {
                self.textureRegistry.unregisterTexture(textureID)
                result(self.error(
                  "attach_v2_cancelled",
                  "The V2 graph was superseded before publication committed."
                ))
              }
              return
            }
            self.sessions[plan.sessionID] = session
            self.applyLatestApplicationActivity()
            self.applyEffectivePlayback(session)
            DispatchQueue.main.async {
              result([
                "textureId": textureID,
                "observedBackend": self.observed(session),
              ])
            }
          }
        }
      } catch {
        candidateSession?.mediaCommitGate.invalidate()
        candidateMediaStates.values.forEach { $0.tearDown() }
        candidateInstalledProgramStates.values.forEach { $0.tearDown() }
        DispatchQueue.main.async {
          self.textureRegistry.unregisterTexture(textureID)
          result(self.error("attach_v2_first_frame_failed", error.localizedDescription))
        }
      }
    }
  }

  func transition(
    arguments: Any?,
    rebuildingResources: Bool,
    result: @escaping FlutterResult
  ) {
    guard let arguments = arguments as? [String: Any] else {
      result(rejectedTransition)
      return
    }
    let preparationTicket = preparationGeneration.begin()
    queue.async { [weak self] in
      guard
        let self,
        Set(arguments.keys) == Set([
          "sessionId", "semanticPlanHash", "qualityPlanHash", "quality",
          "continuityState",
        ]),
        let sessionID = arguments["sessionId"] as? String,
        let session = self.sessions[sessionID],
        session.pendingRecoveryPresentation == nil,
        let semanticPlanHash = arguments["semanticPlanHash"] as? String,
        semanticPlanHash == session.plan.semanticPlanHash,
        let quality = arguments["quality"] as? String,
        Self.qualityLevels.contains(quality),
        let qualityPlanHash = arguments["qualityPlanHash"] as? String,
        session.plan.qualityPlanHashes[quality] == qualityPlanHash,
        let continuity = arguments["continuityState"] as? [String: Any],
        Self.validContinuity(continuity),
        let recoveryPtsMicros = Self.integer(
          continuity["mediaPtsMicros"],
          minimum: 0
        )
      else {
        DispatchQueue.main.async { result(self?.rejectedTransition ?? Self.rejectedTransition) }
        return
      }
      self.applyLatestApplicationActivity()
      let preparationShouldContinue = { [weak self, weak session] in
        guard
          let self,
          let session,
          self.sessions[session.plan.sessionID] === session,
          self.preparationGeneration.isCurrent(preparationTicket)
        else { return false }
        return self.applicationActivitySignal.active ||
          (session.pictureInPictureRetainCount > 0 &&
            session.pictureInPicturePlaying)
      }
      var next = session.plan
      next.quality = quality
      if rebuildingResources {
        let nextMediaStates: [String: MediaState]
        do {
          nextMediaStates = try self.makeMediaStates(
            plan: next,
            reusing: [:],
            liveStatesForBudget: self.liveMediaStatesForDecoderBudget(),
            mediaPtsMicros: recoveryPtsMicros
          )
        } catch {
          DispatchQueue.main.async { result(Self.rejectedTransition) }
          return
        }
        guard self.prepareInitialMedia(
          nextMediaStates,
          shouldContinue: preparationShouldContinue
        ) else {
          nextMediaStates.values.forEach { $0.tearDown() }
          DispatchQueue.main.async { result(Self.rejectedTransition) }
          return
        }
        guard let replacement = self.graphicsResourceFactory() else {
          nextMediaStates.values.forEach { $0.tearDown() }
          DispatchQueue.main.async { result(Self.rejectedTransition) }
          return
        }
        self.applyLatestApplicationActivity()
        guard preparationShouldContinue() else {
          nextMediaStates.values.forEach { $0.tearDown() }
          DispatchQueue.main.async { result(Self.rejectedTransition) }
          return
        }
        next.playing = false
        let now = DispatchTime.now().uptimeNanoseconds
        self.stopCadence(session)
        session.pendingRecoveryPresentation = PendingRecoveryPresentation(
          plan: next,
          mediaStates: nextMediaStates,
          preparationTicket: preparationTicket,
          replacementGraphics: GraphicsResources(
            device: replacement.0,
            ciContext: replacement.1
          ),
          previousRendererAcceptingFrames: session.rendererAcceptingFrames,
          deadlineNanos: now &+ Self.recoveryPresentationTimeoutNanos,
          result: result
        )
        session.presentationArbiter.invalidate(.recovery)
        self.schedulePresentationTimer(session, nowNanos: now)
        return
      }
      guard let device = self.graphics?.device else {
        DispatchQueue.main.async { result(Self.rejectedTransition) }
        return
      }
      do {
        let buffer = try self.renderFrame(
          session: session,
          plan: next,
          device: device,
          strobeFrames: self.strobeFrames(session)
        )
        self.stopCadence(session)
        if session.plan.quality != next.quality {
          session.qualityActivatedAtNanos = DispatchTime.now().uptimeNanoseconds
        }
        session.plan = next
        self.rebindStrobeStates(session, plan: next)
        self.rebindMediaStates(session, plan: next)
        self.rebindRadialProfileStates(session, plan: next)
        self.startCadenceIfNeeded(session)
        DispatchQueue.main.async {
          session.texture.publish(buffer)
          self.textureRegistry.textureFrameAvailable(session.textureID)
          result([
            "accepted": true,
            "observedBackend": self.observed(session),
          ])
        }
      } catch {
        DispatchQueue.main.async { result(Self.rejectedTransition) }
      }
    }
  }

  func updateDocument(arguments: Any?, result: @escaping FlutterResult) {
    guard let requestedPlan = parseAttach(arguments) else {
      result(Self.rejectedTransition)
      return
    }
    let preparationTicket = preparationGeneration.begin()
    queue.async { [weak self] in
      guard
        let self,
        let session = self.sessions[requestedPlan.sessionID],
        session.pendingRecoveryPresentation == nil,
        let device = self.graphics?.device
      else {
        DispatchQueue.main.async { result(Self.rejectedTransition) }
        return
      }
      self.applyLatestApplicationActivity()
      let preparationShouldContinue = { [weak self, weak session] in
        guard
          let self,
          let session,
          self.sessions[session.plan.sessionID] === session,
          self.preparationGeneration.isCurrent(preparationTicket)
        else { return false }
        return self.applicationActivitySignal.active ||
          (session.pictureInPictureRetainCount > 0 &&
            session.pictureInPicturePlaying)
      }
      var next = requestedPlan
      guard let nextMediaStates = try? self.makeMediaStates(
        plan: next,
        reusing: session.mediaStates,
        liveStatesForBudget: self.liveMediaStatesForDecoderBudget()
      ) else {
        DispatchQueue.main.async { result(Self.rejectedTransition) }
        return
      }
      guard self.prepareInitialMedia(
        nextMediaStates,
        shouldContinue: preparationShouldContinue
      ) else {
        nextMediaStates.forEach { id, state in
          if session.mediaStates[id] !== state { state.tearDown() }
        }
        DispatchQueue.main.async { result(Self.rejectedTransition) }
        return
      }
      self.applyLatestApplicationActivity()
      next.playing = SceneRenderV2PlaybackGate.effectivePlayback(
        requestedForegroundPlaying: requestedPlan.playing,
        applicationActive: self.applicationActive,
        pictureInPictureRetained: session.pictureInPictureRetainCount > 0,
        pictureInPicturePlaying: session.pictureInPicturePlaying
      )
      let nextStates = self.makeStrobeStates(
        plan: next,
        reusing: session.strobeStates
      )
      let nextImageReactiveStates = self.makeImageReactiveStates(
        plan: next,
        reusing: session.imageReactiveStates
      )
      let nextRadialProfileStates = self.makeRadialProfileStates(
        plan: next,
        reusing: session.radialProfileStates
      )
      let nextRadialWarpStates = self.makeRadialWarpStates(
        plan: next,
        reusing: session.radialWarpStates
      )
      let nextSnowfallStates = self.makeSnowfallStates(
        plan: next,
        reusing: session.snowfallStates
      )
      let nextPaintedStarlightStates = self.makePaintedStarlightStates(
        plan: next,
        reusing: session.paintedStarlightStates
      )
      let nextMagicStarsStates = self.makeMagicStarsStates(
        plan: next,
        reusing: session.magicStarsStates
      )
      let nextMagicMoonStates = self.makeMagicMoonStates(
        plan: next,
        reusing: session.magicMoonStates
      )
      let nextRadiantEmissionStates = self.makeRadiantEmissionStates(
        plan: next,
        reusing: session.radiantEmissionStates
      )
      let nextRainbowWaterfallStates = self.makeRainbowWaterfallStates(
        plan: next,
        reusing: session.rainbowWaterfallStates
      )
      let nextNeonPulseStates = self.makeNeonPulseStates(
        plan: next,
        reusing: session.neonPulseStates
      )
      let nextEmbeddedScreenStates = self.makeEmbeddedScreenStates(
        plan: next,
        reusing: session.embeddedScreenStates
      )
      let nextWaveformStates = self.makeWaveformStates(
        plan: next,
        reusing: session.waveformStates
      )
      guard let nextInstalledProgramStates = self.makeInstalledProgramStates(
        plan: next,
        reusing: session.installedProgramStates
      ) else {
        nextMediaStates.forEach { id, state in
          if session.mediaStates[id] !== state { state.tearDown() }
        }
        DispatchQueue.main.async { result(Self.rejectedTransition) }
        return
      }
      guard preparationShouldContinue() else {
        nextMediaStates.forEach { id, state in
          if session.mediaStates[id] !== state { state.tearDown() }
        }
        nextInstalledProgramStates.forEach { id, state in
          if session.installedProgramStates[id] !== state { state.tearDown() }
        }
        DispatchQueue.main.async { result(Self.rejectedTransition) }
        return
      }
      do {
        // Render the full replacement before publishing or mutating the
        // active plan. A rejected update therefore leaves the previous graph
        // and pixel buffer authoritative.
        let buffer = try self.renderFrame(
          session: session,
          plan: next,
          device: device,
          strobeFrames: nextStates.mapValues(\.frame),
          imageReactiveStates: nextImageReactiveStates,
          mediaStates: nextMediaStates,
          radialProfileStates: nextRadialProfileStates,
          radialWarpStates: nextRadialWarpStates,
          snowfallStates: nextSnowfallStates,
          paintedStarlightStates: nextPaintedStarlightStates,
          magicStarsStates: nextMagicStarsStates,
          magicMoonStates: nextMagicMoonStates,
          radiantEmissionStates: nextRadiantEmissionStates,
          rainbowWaterfallStates: nextRainbowWaterfallStates,
          neonPulseStates: nextNeonPulseStates,
          embeddedScreenStates: nextEmbeddedScreenStates,
          waveformStates: nextWaveformStates,
          installedProgramStates: nextInstalledProgramStates
        )
        self.stopCadence(session)
        let mediaCommitGate = SceneRenderV2MediaCommitGate()
        guard mediaCommitGate.markRendered() else {
          throw RuntimeError("media_commit_state_invalid")
        }
        let candidatePlan = next
        DispatchQueue.main.async {
          let published = self.preparationGeneration.commitIfCurrent(
            preparationTicket
          ) {
            mediaCommitGate.commitPublication {
              session.texture.publish(buffer)
              self.textureRegistry.textureFrameAvailable(session.textureID)
            }
          }
          // The replacement gate has no session owner until this commit. Keep
          // every candidate alive through transfer or cancellation and reply.
          self.queue.async { [self, session, mediaCommitGate] in
            guard
              published,
              self.preparationGeneration.isCurrent(preparationTicket),
              self.sessions[requestedPlan.sessionID] === session,
              session.pendingRecoveryPresentation == nil
            else {
              let sessionStillAlive =
                self.sessions[requestedPlan.sessionID] === session
              mediaCommitGate.invalidate()
              nextMediaStates.forEach { id, state in
                if session.mediaStates[id] !== state { state.tearDown() }
              }
              nextInstalledProgramStates.forEach { id, state in
                if session.installedProgramStates[id] !== state {
                  state.tearDown()
                }
              }
              if sessionStillAlive { self.startCadenceIfNeeded(session) }
              DispatchQueue.main.async { result(Self.rejectedTransition) }
              return
            }
            let removedMedia = session.mediaStates.filter { id, state in
              nextMediaStates[id] !== state
            }.map(\.value)
            let removedInstalledPrograms = session.installedProgramStates.filter {
              id, state in nextInstalledProgramStates[id] !== state
            }.map(\.value)
            if session.plan.quality != candidatePlan.quality {
              session.qualityActivatedAtNanos =
                DispatchTime.now().uptimeNanoseconds
            }
            session.foregroundPlaying = requestedPlan.playing
            session.mediaCommitGate.invalidate()
            session.mediaCommitGate = mediaCommitGate
            var committedPlan = candidatePlan
            committedPlan.playing = false
            session.plan = committedPlan
            session.strobeStates = nextStates
            session.imageReactiveStates = nextImageReactiveStates
            session.mediaStates = nextMediaStates
            session.radialProfileStates = nextRadialProfileStates
            session.radialWarpStates = nextRadialWarpStates
            session.snowfallStates = nextSnowfallStates
            session.paintedStarlightStates = nextPaintedStarlightStates
            session.magicStarsStates = nextMagicStarsStates
            session.magicMoonStates = nextMagicMoonStates
            session.radiantEmissionStates = nextRadiantEmissionStates
            session.rainbowWaterfallStates = nextRainbowWaterfallStates
            session.neonPulseStates = nextNeonPulseStates
            session.embeddedScreenStates = nextEmbeddedScreenStates
            session.waveformStates = nextWaveformStates
            session.installedProgramStates = nextInstalledProgramStates
            self.rebindStrobeStates(session, plan: committedPlan)
            self.rebindMediaStates(session, plan: committedPlan)
            self.rebindRadialProfileStates(session, plan: committedPlan)
            self.applyLatestApplicationActivity()
            self.applyEffectivePlayback(session, force: true)
            removedMedia.forEach { $0.tearDown() }
            removedInstalledPrograms.forEach { $0.tearDown() }
            DispatchQueue.main.async {
              result([
                "accepted": true,
                "observedBackend": self.observed(session),
              ])
            }
          }
        }
      } catch {
        nextMediaStates.forEach { id, state in
          if session.mediaStates[id] !== state { state.tearDown() }
        }
        nextInstalledProgramStates.forEach { id, state in
          if session.installedProgramStates[id] !== state { state.tearDown() }
        }
        self.startCadenceIfNeeded(session)
        DispatchQueue.main.async { result(Self.rejectedTransition) }
      }
    }
  }

  func updateViewport(arguments: Any?, result: @escaping FlutterResult) {
    guard let arguments = arguments as? [String: Any] else {
      result(error("viewport_v2_invalid", "Invalid V2 viewport."))
      return
    }
    queue.async { [weak self] in
      guard
        let self,
        Set(arguments.keys) == Set([
          "sessionId", "width", "height", "devicePixelRatio",
        ]),
        let sessionID = arguments["sessionId"] as? String,
        let session = self.sessions[sessionID],
        let width = Self.finitePositive(arguments["width"]),
        let height = Self.finitePositive(arguments["height"]),
        let scale = Self.finitePositive(arguments["devicePixelRatio"]),
        let device = self.graphics?.device
      else {
        DispatchQueue.main.async {
          result(self?.error("viewport_v2_invalid", "Invalid V2 viewport."))
        }
        return
      }
      var next = session.plan
      next.width = width
      next.height = height
      next.devicePixelRatio = scale
      do {
        let buffer = try self.renderFrame(
          session: session,
          plan: next,
          device: device,
          strobeFrames: self.strobeFrames(session)
        )
        session.plan = next
        self.rebindStrobeStates(session, plan: next)
        self.rebindRadialProfileStates(session, plan: next)
        DispatchQueue.main.async {
          session.texture.publish(buffer)
          self.textureRegistry.textureFrameAvailable(session.textureID)
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          result(self.error("viewport_v2_render_failed", error.localizedDescription))
        }
      }
    }
  }

  func setPlaying(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      Set(arguments.keys) == Set(["sessionId", "playing"]),
      let sessionID = arguments["sessionId"] as? String,
      let playing = arguments["playing"] as? Bool
    else {
      result(error("playing_v2_invalid", "Invalid V2 playback state."))
      return
    }
    preparationGeneration.invalidate()
    queue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "runtime_v2_unavailable",
            message: "V2 runtime was released.",
            details: nil
          ))
        }
        return
      }
      guard let session = self.sessions[sessionID] else {
        DispatchQueue.main.async {
          result(self.error("session_v2_missing", "Unknown V2 session."))
        }
        return
      }
      session.foregroundPlaying = playing
      self.applyEffectivePlayback(session)
      DispatchQueue.main.async { result(nil) }
    }
  }

  func setApplicationActive(_ active: Bool) {
    guard applicationActivitySignal.setActive(active) else { return }
    queue.async { [weak self] in
      self?.applyLatestApplicationActivity()
    }
  }

  private func applyLatestApplicationActivity() {
    let active = applicationActivitySignal.active
    guard applicationActive != active else { return }
    applicationActive = active
    sessions.values.forEach { applyEffectivePlayback($0) }
  }

  private func applyEffectivePlayback(
    _ session: Session,
    force: Bool = false
  ) {
    let effectivePlaying = SceneRenderV2PlaybackGate.effectivePlayback(
      requestedForegroundPlaying: session.foregroundPlaying,
      applicationActive: applicationActive,
      pictureInPictureRetained: session.pictureInPictureRetainCount > 0,
      pictureInPicturePlaying: session.pictureInPicturePlaying
    )
    let playing = session.mediaCommitGate.shouldPlay(
      effectivePlaying: effectivePlaying
    )
    guard force || playing != session.plan.playing else { return }
    session.plan.playing = playing
    let hostTime = CACurrentMediaTime()
    rebindStrobeStates(session, plan: session.plan)
    session.mediaStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    if playing, let pendingRecovery = session.pendingRecoveryPresentation {
      pendingRecovery.deadlineNanos = DispatchTime.now().uptimeNanoseconds &+
        Self.recoveryPresentationTimeoutNanos
    }
    session.radialProfileStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.radialWarpStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.snowfallStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.paintedStarlightStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.magicStarsStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.magicMoonStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.radiantEmissionStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.rainbowWaterfallStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.neonPulseStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    session.installedProgramStates.values.forEach {
      $0.setPlaying(playing, hostTime: hostTime)
    }
    if playing { startCadenceIfNeeded(session) }
    else { stopCadence(session, suspendingPlayback: true) }
  }

  func updateSignal(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      Set(arguments.keys) == Set(["sessionId", "frameBytes"]),
      let sessionID = arguments["sessionId"] as? String,
      let bytes = (arguments["frameBytes"] as? FlutterStandardTypedData)?.data,
      let frame = SceneRenderSignalFrameV2Codec.decode(bytes)
    else {
      result(error("signal_v2_invalid", "Invalid V2 signal frame."))
      return
    }
    queue.async { [weak self] in
      guard let self, let session = self.sessions[sessionID] else {
        DispatchQueue.main.async {
          result(self?.error("session_v2_missing", "Unknown V2 session."))
        }
        return
      }
      let signalStarted = DispatchTime.now().uptimeNanoseconds
      defer {
        let elapsed = Int(
          (DispatchTime.now().uptimeNanoseconds &- signalStarted) / 1_000
        )
        session.signalUpdates += 1
        session.cumulativeSignalProcessingMicros += elapsed
        session.maximumSignalProcessingMicros = max(
          session.maximumSignalProcessingMicros,
          elapsed
        )
      }
      guard session.pendingSignalPresentation == nil else {
        DispatchQueue.main.async {
          result(self.error(
            "signal_v2_in_flight",
            "The prior V2 signal frame has not been presented yet."
          ))
        }
        return
      }
      guard frame.sequence > session.latestSignalSequence else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      guard session.plan.playing else {
        // Lifecycle suspension makes incoming reactive frames ineligible.
        // Acknowledge and advance the sequence without mutating visual state
        // or arming the presentation loop; Dart normally stops the producer,
        // while this native gate covers a delayed/lost lifecycle handoff.
        session.latestSignalSequence = frame.sequence
        DispatchQueue.main.async { result(nil) }
        return
      }
      guard self.graphics?.device != nil else {
        DispatchQueue.main.async {
          result(self.error(
            "signal_v2_render_failed",
            "The Metal renderer is unavailable."
          ))
        }
        return
      }
      let changed = session.strobeStates.values.filter { $0.consume(frame) }
      let radialChanged = session.plan.playing && session.radialProfileStates.values.reduce(false) {
        let didChange = $1.consume(frame, hostTime: CACurrentMediaTime())
        return $0 || didChange
      }
      let radialWarpChanged = session.radialWarpStates.values.reduce(false) {
        let didChange = $1.consume(frame)
        return $0 || didChange
      }
      let paintedStarlightChanged = session.paintedStarlightStates.values.reduce(false) {
        let didChange = $1.consume(frame)
        return $0 || didChange
      }
      let magicStarsChanged = session.magicStarsStates.values.reduce(false) {
        let didChange = $1.consume(frame)
        return $0 || didChange
      }
      let radiantEmissionChanged = session.radiantEmissionStates.values.reduce(false) {
        let didChange = $1.consume(frame)
        return $0 || didChange
      }
      let rainbowWaterfallChanged = session.rainbowWaterfallStates.values.reduce(false) {
        let didChange = $1.consume(frame)
        return $0 || didChange
      }
      let neonPulseChanged = session.neonPulseStates.values.reduce(false) {
        let didChange = $1.consume(frame)
        return $0 || didChange
      }
      let embeddedScreenChanged = session.plan.nodes.reduce(false) { changed, node in
        guard case .embeddedScreen(let layer) = node,
              let state = session.embeddedScreenStates[layer.id] else { return changed }
        return state.consume(frame, layer: layer) || changed
      }
      let waveformChanged = session.plan.nodes.reduce(false) { changed, node in
        guard case .waveform(let layer) = node,
              let state = session.waveformStates[layer.id] else { return changed }
        return state.consume(frame, layer: layer) || changed
      }
      let installedProgramChanged = session.installedProgramStates.values.reduce(false) {
        $1.consume(frame) || $0
      }
      let mediaReactiveChanged = session.mediaStates.values.reduce(false) {
        $1.consume(frame) || $0
      }
      let imageReactiveChanged = session.imageReactiveStates.values.reduce(false) {
        $1.consume(frame) || $0
      }
      let stateChanged = !changed.isEmpty || radialChanged || radialWarpChanged ||
        paintedStarlightChanged || magicStarsChanged || radiantEmissionChanged ||
        rainbowWaterfallChanged || neonPulseChanged || embeddedScreenChanged ||
        waveformChanged || installedProgramChanged || mediaReactiveChanged ||
        imageReactiveChanged
      guard stateChanged || session.signalStateNeedsPresentation else {
        session.latestSignalSequence = frame.sequence
        DispatchQueue.main.async { result(nil) }
        return
      }
      session.signalStateNeedsPresentation = true
      let hasTimedFlash = changed.contains {
        $0.program == .transparentProStrobe
      }
      if hasTimedFlash {
        session.flashWorkItem?.cancel()
        session.flashWorkItem = nil
        session.flashHideStartedNanos = 0
        session.presentationArbiter.discard(.flashHide)
      }
      let now = DispatchTime.now().uptimeNanoseconds
      session.pendingSignalPresentation = PendingSignalPresentation(
        sequence: frame.sequence,
        deadlineNanos: now &+ Self.signalPresentationTimeoutNanos,
        hasTimedFlash: hasTimedFlash,
        result: result
      )
      session.presentationArbiter.invalidate(.signal)
      self.schedulePresentationTimer(session, nowNanos: now)
    }
  }

  private func makeStrobeStates(
    plan: Plan,
    reusing current: [String: StrobeState] = [:]
  ) -> [String: StrobeState] {
    var result = [String: StrobeState]()
    for node in plan.nodes {
      guard case .strobe(let layer, _) = node else { continue }
      if let existing = current[layer.id], existing.program == layer.program {
        result[layer.id] = existing
      } else {
        result[layer.id] = StrobeState(plan: plan, layer: layer)
      }
    }
    return result
  }

  private func makeImageReactiveStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2NaturalReactiveLightState] = [:]
  ) -> [String: SceneRenderV2NaturalReactiveLightState] {
    var result = [String: SceneRenderV2NaturalReactiveLightState]()
    for node in plan.nodes {
      guard case .image(let layer, _) = node,
            let config = layer.naturalReactiveLight else { continue }
      if let existing = current[layer.id], existing.config == config {
        result[layer.id] = existing
      } else {
        result[layer.id] = SceneRenderV2NaturalReactiveLightState(config: config)
      }
    }
    return result
  }

  private func makeMediaStates(
    plan: Plan,
    reusing current: [String: MediaState] = [:],
    liveStatesForBudget: [MediaState]? = nil,
    mediaPtsMicros: Int64? = nil
  ) throws -> [String: MediaState] {
    let layers = plan.nodes.compactMap { node -> MediaLayer? in
      guard case .media(let layer) = node else { return nil }
      return layer
    }
    guard layers.filter({ $0.kind.isVideo }).count <= 2 else {
      throw RuntimeError("video_decoder_budget_exceeded")
    }
    let reused = layers.compactMap { layer -> MediaState? in
      guard let state = current[layer.id], state.canReuse(for: layer) else {
        return nil
      }
      return state
    }
    let newDecoderCount = layers.filter { layer in
      layer.kind.isVideo && !reused.contains(where: { $0.id == layer.id })
    }.count
    let budgetStates = liveStatesForBudget ?? Array(current.values)
    let liveDecoderCount = Set(
      budgetStates.filter { $0.decoderCount > 0 }.map(ObjectIdentifier.init)
    ).count
    guard sceneRenderV2DecoderTransitionWithinBudget(
      liveDecoderCount: liveDecoderCount,
      newDecoderCount: newDecoderCount
    ) else {
      throw RuntimeError("video_decoder_transition_budget_exceeded")
    }
    var result = [String: MediaState]()
    var created = [MediaState]()
    do {
      for layer in layers {
        if let state = current[layer.id], state.canReuse(for: layer) {
          result[layer.id] = state
        } else {
          let state = try MediaState(
            layer: layer,
            mediaPtsMicros: mediaPtsMicros ?? plan.mediaPtsMicros,
            ownerQueue: queue
          )
          created.append(state)
          result[layer.id] = state
        }
      }
      return result
    } catch {
      created.forEach { $0.tearDown() }
      throw error
    }
  }

  private func liveMediaStatesForDecoderBudget() -> [MediaState] {
    var unique = [ObjectIdentifier: MediaState]()
    for session in sessions.values {
      for state in session.mediaStates.values where state.decoderCount > 0 {
        unique[ObjectIdentifier(state)] = state
      }
      if let pending = session.pendingRecoveryPresentation {
        for state in pending.mediaStates.values where state.decoderCount > 0 {
          unique[ObjectIdentifier(state)] = state
        }
      }
    }
    return Array(unique.values)
  }

  private func makeRadialProfileStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2RadialProfileState] = [:]
  ) -> [String: SceneRenderV2RadialProfileState] {
    var result = [String: SceneRenderV2RadialProfileState]()
    for node in plan.nodes {
      guard case .radialProfile(let layer) = node else { continue }
      if let existing = current[layer.id], existing.canReuse(for: layer) {
        result[layer.id] = existing
      } else {
        result[layer.id] = SceneRenderV2RadialProfileState(layer: layer)
      }
    }
    return result
  }

  private func makeRadialWarpStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2RadialWarpState] = [:]
  ) -> [String: SceneRenderV2RadialWarpState] {
    var result = [String: SceneRenderV2RadialWarpState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .radialWarp(let layer) = node else { continue }
      let state = current[layer.id] ?? SceneRenderV2RadialWarpState(layerID: layer.id)
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makeSnowfallStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2SnowfallState] = [:]
  ) -> [String: SceneRenderV2SnowfallState] {
    var result = [String: SceneRenderV2SnowfallState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .snowfall(let layer) = node else { continue }
      let state = current[layer.id] ?? SceneRenderV2SnowfallState(layerID: layer.id)
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makePaintedStarlightStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2PaintedStarlightState] = [:]
  ) -> [String: SceneRenderV2PaintedStarlightState] {
    var result = [String: SceneRenderV2PaintedStarlightState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .paintedStarlight(let layer) = node else { continue }
      let state = current[layer.id] ?? SceneRenderV2PaintedStarlightState(layerID: layer.id)
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makeMagicStarsStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2MagicStarsState] = [:]
  ) -> [String: SceneRenderV2MagicStarsState] {
    var result = [String: SceneRenderV2MagicStarsState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .magicStars(let layer) = node else { continue }
      let existing = current[layer.id]
      let state = existing?.randomSeed == SceneRenderV2MagicStarsState.nodeSeed(
        sessionSeed: plan.sessionSeed,
        nodeID: layer.id
      )
        ? existing!
        : SceneRenderV2MagicStarsState(
          layerID: layer.id,
          sessionSeed: plan.sessionSeed
        )
      state.applyControls(layer.controls)
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makeMagicMoonStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2MagicMoonState] = [:]
  ) -> [String: SceneRenderV2MagicMoonState] {
    var result = [String: SceneRenderV2MagicMoonState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .magicMoon(let layer) = node else { continue }
      let state = current[layer.id] ?? SceneRenderV2MagicMoonState(layerID: layer.id)
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makeRadiantEmissionStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2RadiantEmissionState] = [:]
  ) -> [String: SceneRenderV2RadiantEmissionState] {
    var result = [String: SceneRenderV2RadiantEmissionState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .radiantEmission(let layer) = node else { continue }
      let state = current[layer.id] ?? SceneRenderV2RadiantEmissionState(layerID: layer.id)
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makeRainbowWaterfallStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2RainbowWaterfallState] = [:]
  ) -> [String: SceneRenderV2RainbowWaterfallState] {
    var result = [String: SceneRenderV2RainbowWaterfallState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .rainbowWaterfall(let layer) = node else { continue }
      let state = current[layer.id] ?? SceneRenderV2RainbowWaterfallState(layerID: layer.id)
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makeNeonPulseStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2NeonPulseState] = [:]
  ) -> [String: SceneRenderV2NeonPulseState] {
    var result = [String: SceneRenderV2NeonPulseState]()
    let now = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .neonPulse(let layer) = node else { continue }
      let expectedSeed = SceneRenderV2NeonPulseState.nodeSeed(
        sessionSeed: plan.sessionSeed,
        nodeID: layer.id
      )
      let existing = current[layer.id]
      let state = existing?.randomSeed == expectedSeed
        ? existing!
        : SceneRenderV2NeonPulseState(
          layerID: layer.id,
          sessionSeed: plan.sessionSeed
        )
      state.controls = layer.controls
      state.setPlaying(plan.playing, hostTime: now)
      result[layer.id] = state
    }
    return result
  }

  private func makeEmbeddedScreenStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2EmbeddedScreenState] = [:]
  ) -> [String: SceneRenderV2EmbeddedScreenState] {
    var result = [String: SceneRenderV2EmbeddedScreenState]()
    for node in plan.nodes {
      guard case .embeddedScreen(let layer) = node else { continue }
      result[layer.id] = current[layer.id] ?? SceneRenderV2EmbeddedScreenState(
        layerID: layer.id
      )
    }
    return result
  }

  private func makeWaveformStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2WaveformState] = [:]
  ) -> [String: SceneRenderV2WaveformState] {
    var result = [String: SceneRenderV2WaveformState]()
    for node in plan.nodes {
      guard case .waveform(let layer) = node else { continue }
      result[layer.id] = current[layer.id] ?? SceneRenderV2WaveformState(layerID: layer.id)
    }
    return result
  }

  private func makeInstalledProgramStates(
    plan: Plan,
    reusing current: [String: SceneRenderV2InstalledProgramState] = [:]
  ) -> [String: SceneRenderV2InstalledProgramState]? {
    var result = [String: SceneRenderV2InstalledProgramState]()
    var created = [SceneRenderV2InstalledProgramState]()
    let hostTime = CACurrentMediaTime()
    for node in plan.nodes {
      guard case .installedProgram(let layer) = node else { continue }
      if let existing = current[layer.id], existing.canReuse(for: layer) {
        existing.setPlaying(plan.playing, hostTime: hostTime)
        result[layer.id] = existing
        continue
      }
      guard let state = SceneRenderV2InstalledProgramState(
        layer: layer,
        sceneSessionID: plan.sessionID,
        playing: plan.playing,
        renderEngine: renderEngine,
        metalContext: metalContext
      ) else {
        created.forEach { $0.tearDown() }
        return nil
      }
      created.append(state)
      result[layer.id] = state
    }
    return result
  }

  private func prepareInitialMedia(
    _ states: [String: MediaState],
    shouldContinue: () -> Bool
  ) -> Bool {
    let deadline = DispatchTime.now() + .milliseconds(
      Self.mediaPrerollTimeoutMilliseconds
    )
    for state in states.values where !state.hasCompleteFrame {
      guard shouldContinue() else { return false }
      applyLatestApplicationActivity()
      guard state.prepareInitialFrame(
        deadline: deadline,
        onWait: applyLatestApplicationActivity,
        shouldContinue: shouldContinue
      ) else {
        return false
      }
    }
    applyLatestApplicationActivity()
    return shouldContinue()
  }

  private func rebindMediaStates(_ session: Session, plan: Plan) {
    for node in plan.nodes {
      guard case .media(let layer) = node,
            let state = session.mediaStates[layer.id],
            state.canReuse(for: layer) else { continue }
      state.rebind(layer)
    }
  }

  private func rebindStrobeStates(_ session: Session, plan: Plan) {
    for node in plan.nodes {
      guard case .strobe(let layer, _) = node else { continue }
      session.strobeStates[layer.id]?.rebind(plan: plan, layer: layer)
    }
  }

  private func rebindRadialProfileStates(_ session: Session, plan: Plan) {
    for node in plan.nodes {
      guard case .radialProfile(let layer) = node,
            let state = session.radialProfileStates[layer.id],
            state.canReuse(for: layer) else { continue }
      state.rebind(layer)
    }
  }

  private func strobeFrames(_ session: Session) -> [String: StrobeFrame] {
    session.strobeStates.mapValues(\.frame)
  }

  private func startCadenceIfNeeded(_ session: Session) {
    let nowNanos = DispatchTime.now().uptimeNanoseconds
    if session.plan.playing, session.plan.continuousFramesPerSecond > 0 {
      session.lastCadenceTickNanos = nowNanos
      session.cadenceDeadlineNanos = nowNanos &+ cadenceIntervalNanos(session.plan)
    } else {
      session.lastCadenceTickNanos = 0
      session.cadenceDeadlineNanos = 0
    }
    schedulePresentationTimer(session, nowNanos: nowNanos)
  }

  private func stopCadence(
    _ session: Session,
    suspendingPlayback: Bool = false
  ) {
    session.cadenceTimer?.setEventHandler {}
    session.cadenceTimer?.cancel()
    session.cadenceTimer = nil
    session.presentationDeadlineNanos = 0
    session.cadenceDeadlineNanos = 0
    session.lastCadenceTickNanos = 0
    if suspendingPlayback {
      session.presentationArbiter.discardForPlaybackSuspension(.cadence)
      discardQueuedSignalForPlaybackSuspension(session)
    }
    schedulePresentationTimer(session)
  }

  private func discardQueuedSignalForPlaybackSuspension(_ session: Session) {
    guard !session.presentationArbiter.inFlightReasons.contains(.signal) else {
      return
    }
    let pending = session.pendingSignalPresentation
    session.pendingSignalPresentation = nil
    session.signalStateNeedsPresentation = false
    session.presentationArbiter.discardForPlaybackSuspension(.signal)
    guard let pending else { return }
    session.latestSignalSequence = max(
      session.latestSignalSequence,
      pending.sequence
    )
    if pending.hasTimedFlash {
      session.flashWorkItem?.cancel()
      session.flashWorkItem = nil
      session.strobeStates.values.forEach { _ = $0.hideTimedFlash() }
      session.flashRestoreBuffer = nil
      session.flashHideStartedNanos = 0
      session.presentationArbiter.discardForPlaybackSuspension(.flashHide)
    }
    DispatchQueue.main.async { pending.result(nil) }
  }

  private func tearDownPresentation(_ session: Session) {
    session.mediaCommitGate.invalidate()
    session.cadenceTimer?.setEventHandler {}
    session.cadenceTimer?.cancel()
    session.cadenceTimer = nil
    session.presentationDeadlineNanos = 0
    session.cadenceDeadlineNanos = 0
    session.lastCadenceTickNanos = 0
    session.flashWorkItem?.cancel()
    session.flashWorkItem = nil
    session.flashRestoreBuffer = nil
    session.flashHideStartedNanos = 0
    let pending = session.pendingSignalPresentation
    session.pendingSignalPresentation = nil
    let pendingRecovery = session.pendingRecoveryPresentation
    session.pendingRecoveryPresentation = nil
    pendingRecovery?.mediaCommitGate.invalidate()
    pendingRecovery?.mediaStates.forEach { id, state in
      if session.mediaStates[id] !== state { state.tearDown() }
    }
    session.presentationArbiter.reset()
    if let pending {
      DispatchQueue.main.async {
        pending.result(FlutterError(
          code: "signal_v2_cancelled",
          message: "The V2 scene session ended before the signal was presented.",
          details: nil
        ))
      }
    }
    if let pendingRecovery {
      DispatchQueue.main.async { pendingRecovery.result(Self.rejectedTransition) }
    }
  }

  private func scheduleFlashHide(_ session: Session) {
    session.flashWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self, weak session] in
      guard
        let self,
        let session,
        self.sessions[session.plan.sessionID] === session
      else { return }
      guard session.strobeStates.values.contains(where: { $0.hideTimedFlash() }) else {
        return
      }
      session.flashWorkItem = nil
      let now = DispatchTime.now().uptimeNanoseconds
      session.flashHideStartedNanos = now
      session.presentationArbiter.invalidate(.flashHide)
      self.schedulePresentationTimer(session, nowNanos: now)
    }
    session.flashWorkItem = work
    queue.asyncAfter(
      deadline: .now() + .nanoseconds(Int(Self.flashVisibleDurationNanos)),
      execute: work
    )
  }

  private func cadenceIntervalNanos(_ plan: Plan) -> UInt64 {
    UInt64(max(
      1,
      Int((1_000_000_000.0 / Double(presentationFramesPerSecond(plan))).rounded())
    ))
  }

  private var physicalPresentationIntervalNanos: UInt64 {
    UInt64(max(
      1,
      Int((1_000_000_000.0 /
        Double(maximumPresentationFramesPerSecond)).rounded())
    ))
  }

  private func nextPhysicalPresentationSlot(after nowNanos: UInt64) -> UInt64 {
    let interval = physicalPresentationIntervalNanos
    return ((nowNanos / interval) &+ 1) &* interval
  }

  private func physicalSlot(at nowNanos: UInt64) -> UInt64 {
    nowNanos / physicalPresentationIntervalNanos
  }

  private func schedulePresentationTimer(
    _ session: Session,
    nowNanos: UInt64 = DispatchTime.now().uptimeNanoseconds
  ) {
    let hasPendingInvalidation =
      !session.presentationArbiter.pendingReasons.isEmpty
    let renderInFlight = session.presentationArbiter.renderInFlight
    guard sceneRenderV2ShouldSchedulePresentationTimer(
      playing: session.plan.playing,
      hasCadenceDeadline: session.cadenceDeadlineNanos > 0,
      hasPendingInvalidation: hasPendingInvalidation,
      renderInFlight: renderInFlight
    ) else {
      session.cadenceTimer?.setEventHandler {}
      session.cadenceTimer?.cancel()
      session.cadenceTimer = nil
      session.presentationDeadlineNanos = 0
      return
    }
    let hasPendingPresentation = hasPendingInvalidation || renderInFlight
    var deadlineNanos: UInt64?
    if session.cadenceDeadlineNanos > 0 {
      let interval = physicalPresentationIntervalNanos
      let aligned = ((session.cadenceDeadlineNanos &+ interval &- 1) / interval) &*
        interval
      deadlineNanos = aligned
    }
    if hasPendingPresentation {
      let nextSlot = nextPhysicalPresentationSlot(after: nowNanos)
      deadlineNanos = min(deadlineNanos ?? nextSlot, nextSlot)
    }
    guard var target = deadlineNanos else {
      session.cadenceTimer?.setEventHandler {}
      session.cadenceTimer?.cancel()
      session.cadenceTimer = nil
      session.presentationDeadlineNanos = 0
      return
    }
    if session.presentationDeadlineNanos > nowNanos {
      target = min(target, session.presentationDeadlineNanos)
    }
    if session.cadenceTimer == nil {
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.setEventHandler { [weak self, weak session] in
        guard
          let self,
          let session,
          self.sessions[session.plan.sessionID] === session
        else { return }
        session.presentationDeadlineNanos = 0
        self.handlePresentationSlot(session)
      }
      session.cadenceTimer = timer
      timer.resume()
    }
    session.presentationDeadlineNanos = target
    session.cadenceTimer?.schedule(
      deadline: DispatchTime(uptimeNanoseconds: target),
      repeating: .never,
      leeway: .milliseconds(1)
    )
  }

  private func handlePresentationSlot(_ session: Session) {
    let now = DispatchTime.now().uptimeNanoseconds
    advanceCadenceIfDue(session, nowNanos: now)
    if !session.presentationArbiter.renderInFlight,
       let pending = session.pendingSignalPresentation,
       now >= pending.deadlineNanos {
      failPendingSignal(
        session,
        code: "signal_v2_presentation_timeout",
        message: "The V2 signal frame was not presented before its deadline."
      )
    }
    if !session.presentationArbiter.renderInFlight,
       let pending = session.pendingRecoveryPresentation,
       now >= pending.deadlineNanos {
      failPendingRecovery(session)
    }
    let slot = physicalSlot(at: now)
    switch session.presentationArbiter.beginPresentation(slot: slot) {
    case .idle, .wait:
      schedulePresentationTimer(session, nowNanos: now)
    case .submit(let token):
      submitPresentation(session, token: token, nowNanos: now)
    }
  }

  private func advanceCadenceIfDue(_ session: Session, nowNanos: UInt64) {
    guard
      session.plan.playing,
      session.cadenceDeadlineNanos > 0,
      nowNanos >= session.cadenceDeadlineNanos
    else { return }
    let intervalNanos = cadenceIntervalNanos(session.plan)
    session.cadenceTicks += 1
    if nowNanos > session.cadenceDeadlineNanos {
      session.maximumCadenceLatenessMicros = max(
        session.maximumCadenceLatenessMicros,
        Int((nowNanos &- session.cadenceDeadlineNanos) / 1_000)
      )
    }
    let deltaMicros = Int64(
      (nowNanos &- session.lastCadenceTickNanos) / 1_000
    )
    session.lastCadenceTickNanos = nowNanos
    var skippedPeriods = 0
    repeat {
      session.cadenceDeadlineNanos &+= intervalNanos
      if session.cadenceDeadlineNanos <= nowNanos { skippedPeriods += 1 }
    } while session.cadenceDeadlineNanos <= nowNanos
    session.cadenceSkippedPeriods += skippedPeriods
    let strobeChanged = session.strobeStates.values.reduce(false) {
      $1.advance(by: max(0, deltaMicros)) || $0
    }
    let hostTime = CACurrentMediaTime()
    let mediaChanged = session.mediaStates.values.reduce(false) {
      $1.prepareFrame(hostTime: hostTime) || $0
    }
    let radialProfileChanged = session.radialProfileStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let radialWarpChanged = session.radialWarpStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let snowfallChanged = session.snowfallStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let paintedStarlightChanged = session.paintedStarlightStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let magicStarsChanged = session.magicStarsStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let magicMoonChanged = session.magicMoonStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let radiantEmissionChanged = session.radiantEmissionStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let rainbowWaterfallChanged = session.rainbowWaterfallStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let neonPulseChanged = session.neonPulseStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let installedProgramChanged = session.installedProgramStates.values.reduce(false) {
      $1.advance(hostTime: hostTime) || $0
    }
    let changed = strobeChanged || mediaChanged || radialProfileChanged ||
      radialWarpChanged || snowfallChanged || paintedStarlightChanged ||
      magicStarsChanged || magicMoonChanged || radiantEmissionChanged ||
      rainbowWaterfallChanged || neonPulseChanged || installedProgramChanged
    guard changed else {
      session.cadenceNoChangeTicks += 1
      return
    }
    // A new logical state arrived before the prior authored opportunity was
    // committed. That is one real miss, regardless of how many faster display
    // refreshes elapsed while its render/publish callback was in flight.
    session.presentationArbiter.recordCurrentOpportunityMiss()
    session.presentationArbiter.recordSkippedOpportunities(skippedPeriods)
    session.presentationArbiter.invalidate(.cadence)
  }

  private func submitPresentation(
    _ session: Session,
    token: SceneRenderV2PresentationToken,
    nowNanos: UInt64
  ) {
    if token.reasons.contains(.flashHide),
       session.flashHideStartedNanos > 0,
       nowNanos &- session.flashHideStartedNanos >=
         Self.flashHidePresentationTimeoutNanos,
       let restore = session.flashRestoreBuffer {
      publishPresentation(
        restore,
        session: session,
        token: token,
        fulfilledReasons: [.flashHide]
      )
      return
    }
    if token.reasons.contains(.recovery),
       let pending = session.pendingRecoveryPresentation {
      submitRecoveryPresentation(
        session,
        pending: pending,
        token: token,
        nowNanos: nowNanos
      )
      return
    }
    guard let device = graphics?.device else {
      failPresentation(
        session,
        token: token,
        error: RuntimeError("graphics_context_unavailable")
      )
      return
    }
    do {
      let buffer = try renderFrame(
        session: session,
        plan: session.plan,
        device: device,
        strobeFrames: strobeFrames(session)
      )
      publishPresentation(
        buffer,
        session: session,
        token: token,
        fulfilledReasons: token.reasons
      )
    } catch let runtimeError as RuntimeError where runtimeError.isBackpressure {
      session.pixelBufferBackpressureEvents += 1
      session.presentationArbiter.retryPresentation(token)
      schedulePresentationTimer(session, nowNanos: nowNanos)
    } catch {
      failPresentation(session, token: token, error: error)
    }
  }

  private func submitRecoveryPresentation(
    _ session: Session,
    pending: PendingRecoveryPresentation,
    token: SceneRenderV2PresentationToken,
    nowNanos: UInt64
  ) {
    guard session.pendingRecoveryPresentation === pending else {
      session.presentationArbiter.failPresentation(
        token,
        failedReasons: .recovery
      )
      schedulePresentationTimer(session, nowNanos: nowNanos)
      return
    }
    let previousGraphics = graphics
    graphics = pending.replacementGraphics
    do {
      let buffer = try renderFrame(
        session: session,
        plan: pending.plan,
        device: pending.replacementGraphics.device,
        strobeFrames: strobeFrames(session),
        mediaStates: pending.mediaStates
      )
      guard pending.mediaCommitGate.markRendered() else {
        throw RuntimeError("media_commit_state_invalid")
      }
      // Keep the current graph and graphics authority untouched until the
      // replacement buffer wins the generation fence on the main thread.
      graphics = previousGraphics
      publishPresentation(
        buffer,
        session: session,
        token: token,
        fulfilledReasons: token.reasons
      )
    } catch let runtimeError as RuntimeError where runtimeError.isBackpressure {
      graphics = previousGraphics
      session.rendererAcceptingFrames = pending.previousRendererAcceptingFrames
      session.pixelBufferBackpressureEvents += 1
      session.presentationArbiter.retryPresentation(token)
      schedulePresentationTimer(session, nowNanos: nowNanos)
    } catch {
      graphics = previousGraphics
      session.rendererAcceptingFrames = pending.previousRendererAcceptingFrames
      session.presentationArbiter.failPresentation(
        token,
        failedReasons: .recovery
      )
      failPendingRecovery(session)
      schedulePresentationTimer(session, nowNanos: nowNanos)
    }
  }

  private func publishPresentation(
    _ buffer: CVPixelBuffer,
    session: Session,
    token: SceneRenderV2PresentationToken,
    fulfilledReasons: SceneRenderV2PresentationInvalidation
  ) {
    if token.reasons.contains(.signal),
       session.pendingSignalPresentation?.hasTimedFlash == true,
       session.flashRestoreBuffer == nil {
      session.flashRestoreBuffer = session.texture.latestPixelBuffer()
    }
    let recoveryPublication = fulfilledReasons.contains(.recovery)
      ? session.pendingRecoveryPresentation
      : nil
    DispatchQueue.main.async { [weak self, weak session] in
      guard let self, let session else { return }
      let published: Bool
      if let recoveryPublication {
        published = self.preparationGeneration.commitIfCurrent(
          recoveryPublication.preparationTicket
        ) {
          recoveryPublication.mediaCommitGate.commitPublication {
            session.texture.publish(buffer)
            self.textureRegistry.textureFrameAvailable(session.textureID)
          }
        }
      } else {
        session.texture.publish(buffer)
        self.textureRegistry.textureFrameAvailable(session.textureID)
        published = true
      }
      guard published else {
        self.queue.async { [weak self, weak session] in
          guard
            let self,
            let session,
            let recoveryPublication,
            self.sessions[session.plan.sessionID] === session,
            session.pendingRecoveryPresentation === recoveryPublication
          else { return }
          session.presentationArbiter.failPresentation(
            token,
            failedReasons: .recovery
          )
          self.failPendingRecovery(session)
          self.schedulePresentationTimer(session)
        }
        return
      }
      let publishedSlot = self.physicalSlot(
        at: DispatchTime.now().uptimeNanoseconds
      )
      self.queue.async { [weak self, weak session] in
        guard
          let self,
          let session,
          self.sessions[session.plan.sessionID] === session
        else { return }
        session.presentationArbiter.completePresentation(
          token,
          publishedSlot: publishedSlot,
          fulfilledReasons: fulfilledReasons
        )
        if token.reasons.contains(.cadence),
           fulfilledReasons.contains(.cadence) {
          session.cadenceRenders += 1
        }
        if fulfilledReasons.contains(.flashHide) {
          session.flashRestoreBuffer = nil
          session.flashHideStartedNanos = 0
          session.presentationArbiter.discard(.flashHide)
        }
        if token.reasons.contains(.signal) {
          if fulfilledReasons.contains(.signal) {
            session.signalRenders += 1
            let pending = session.pendingSignalPresentation
            session.pendingSignalPresentation = nil
            if let pending {
              session.latestSignalSequence = max(
                session.latestSignalSequence,
                pending.sequence
              )
              session.signalStateNeedsPresentation = false
            }
            if pending?.hasTimedFlash == true {
              self.scheduleFlashHide(session)
            }
            if let pending {
              DispatchQueue.main.async { pending.result(nil) }
            }
          } else {
            self.failPendingSignal(
              session,
              code: "signal_v2_render_failed",
              message: "The complete V2 signal frame could not be presented."
            )
          }
        }
        if fulfilledReasons.contains(.recovery),
           let pending = session.pendingRecoveryPresentation {
          guard
            self.preparationGeneration.isCurrent(pending.preparationTicket),
            pending.mediaCommitGate.phase == .published
          else {
            self.failPendingRecovery(session)
            return
          }
          let removedMedia = Array(session.mediaStates.values)
          if session.plan.quality != pending.plan.quality {
            session.qualityActivatedAtNanos =
              DispatchTime.now().uptimeNanoseconds
          }
          self.graphics = pending.replacementGraphics
          session.mediaCommitGate.invalidate()
          session.mediaCommitGate = pending.mediaCommitGate
          pending.plan.playing = false
          session.plan = pending.plan
          session.mediaStates = pending.mediaStates
          self.rebindStrobeStates(session, plan: pending.plan)
          self.rebindMediaStates(session, plan: pending.plan)
          self.rebindRadialProfileStates(session, plan: pending.plan)
          session.pendingRecoveryPresentation = nil
          self.applyLatestApplicationActivity()
          self.applyEffectivePlayback(session, force: true)
          removedMedia.forEach { $0.tearDown() }
          DispatchQueue.main.async {
            pending.result([
              "accepted": true,
              "observedBackend": self.observed(session),
            ])
          }
        }
        self.schedulePresentationTimer(session)
      }
    }
  }

  private func failPresentation(
    _ session: Session,
    token: SceneRenderV2PresentationToken,
    error: Error
  ) {
    session.rendererAcceptingFrames = false
    let requiresFlashRestore =
      token.reasons.contains(.flashHide) ||
      (token.reasons.contains(.signal) &&
        session.pendingSignalPresentation?.hasTimedFlash == true)
    if requiresFlashRestore, let restore = session.flashRestoreBuffer {
      session.strobeStates.values.forEach { _ = $0.hideTimedFlash() }
      session.cadenceDeadlineNanos = 0
      publishPresentation(
        restore,
        session: session,
        token: token,
        fulfilledReasons: [.flashHide]
      )
      return
    }
    session.presentationArbiter.failPresentation(token)
    if token.reasons.contains(.signal) {
      failPendingSignal(
        session,
        code: "signal_v2_render_failed",
        message: error.localizedDescription
      )
    }
    if token.reasons.contains(.flashHide) {
      session.strobeStates.values.forEach { _ = $0.hideTimedFlash() }
      session.flashRestoreBuffer = nil
      session.flashHideStartedNanos = 0
    }
    if token.reasons.contains(.cadence) {
      session.cadenceDeadlineNanos = 0
      session.lastCadenceTickNanos = 0
    }
    schedulePresentationTimer(session)
  }

  private func failPendingSignal(
    _ session: Session,
    code: String,
    message: String
  ) {
    guard let pending = session.pendingSignalPresentation else { return }
    session.pendingSignalPresentation = nil
    session.presentationArbiter.discard(.signal)
    if pending.hasTimedFlash {
      session.flashWorkItem?.cancel()
      session.flashWorkItem = nil
      if session.strobeStates.values.contains(where: { $0.hideTimedFlash() }),
         session.flashRestoreBuffer != nil {
        session.flashHideStartedNanos = DispatchTime.now().uptimeNanoseconds
        session.presentationArbiter.invalidate(.flashHide)
      }
    }
    DispatchQueue.main.async {
      pending.result(FlutterError(code: code, message: message, details: nil))
    }
  }

  private func failPendingRecovery(_ session: Session) {
    guard let pending = session.pendingRecoveryPresentation else { return }
    session.pendingRecoveryPresentation = nil
    pending.mediaCommitGate.invalidate()
    session.presentationArbiter.discard(.recovery)
    pending.mediaStates.forEach { id, state in
      if session.mediaStates[id] !== state { state.tearDown() }
    }
    session.rendererAcceptingFrames = pending.previousRendererAcceptingFrames
    startCadenceIfNeeded(session)
    DispatchQueue.main.async { pending.result(Self.rejectedTransition) }
  }

  func metrics(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      Set(arguments.keys) == Set(["sessionId"]),
      let sessionID = arguments["sessionId"] as? String
    else {
      result(error("metrics_v2_invalid", "Invalid V2 metrics request."))
      return
    }
    queue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "runtime_v2_unavailable",
            message: "V2 runtime was released.",
            details: nil
          ))
        }
        return
      }
      guard let session = self.sessions[sessionID] else {
        DispatchQueue.main.async {
          result(self.error("session_v2_missing", "Unknown V2 session."))
        }
        return
      }
      session.metricsSequence += 1
      let now = DispatchTime.now().uptimeNanoseconds
      let windowMicros = max(1, Int((now &- session.lastMetricsNanos) / 1_000))
      session.lastMetricsNanos = now
      session.lastMetricsCompleted = session.completed
      let noChangeDelta = max(
        0,
        session.cadenceNoChangeTicks - session.lastMetricsCadenceNoChangeTicks
      )
      session.lastMetricsCadenceNoChangeTicks = session.cadenceNoChangeTicks
      session.lastMetricsCadenceSkippedPeriods = session.cadenceSkippedPeriods
      session.lastMetricsBackpressureEvents =
        session.pixelBufferBackpressureEvents
      let scheduledDeadlines = session.plan.playing &&
        session.plan.continuousFramesPerSecond > 0
        ? max(
          0,
          Int(
            (Double(self.presentationFramesPerSecond(session.plan)) *
              Double(windowMicros) / 1_000_000).rounded()
          )
        )
        : 0
      // The presentation arbiter records each logical authored opportunity
      // before submission. Faster physical refreshes cap publication without
      // manufacturing extra cadence deadlines or hiding accidental over-render.
      let deadlineWindow = session.presentationArbiter.drainMetrics()
      let authoredDeadlines = deadlineWindow.authoredDeadlines
      let renderedFrames = deadlineWindow.renderedFrames
      let deadlineMisses = deadlineWindow.deadlineMisses
      let maximumConsecutiveMisses =
        deadlineWindow.maximumConsecutiveDeadlineMisses
      session.cumulativeAuthoredDeadlines += authoredDeadlines
      session.cumulativeRenderedFrames += renderedFrames
      session.cumulativeDeadlineMisses += deadlineMisses
      session.cumulativeMaximumConsecutiveDeadlineMisses = max(
        session.cumulativeMaximumConsecutiveDeadlineMisses,
        maximumConsecutiveMisses
      )
      let samples = session.renderMicros
      session.renderMicros.removeAll(keepingCapacity: true)
      session.maximumConsecutiveRenderFailures = 0
      let effectiveFramesPerSecond = self.presentationFramesPerSecond(
        session.plan
      )
      let payload: [String: Any] = [
        "sequence": session.metricsSequence,
        "windowDurationMicros": windowMicros,
        "quality": session.plan.quality,
        "targetFramesPerSecond": effectiveFramesPerSecond,
        "authoredDeadlines": authoredDeadlines,
        "renderedFrames": renderedFrames,
        "deadlineMisses": deadlineMisses,
        "maximumConsecutiveDeadlineMisses": maximumConsecutiveMisses,
        "renderP95Micros": Self.percentile(samples, fraction: 0.95),
        "renderP99Micros": Self.percentile(samples, fraction: 0.99),
        "rendererAcceptingFrames": session.rendererAcceptingFrames,
        "decoderProducingFrames": session.mediaStates.values
          .filter { $0.decoderCount > 0 }
          .allSatisfy(\.hasCompleteFrame),
        "completeFramePresented": session.completeFramePresented,
      ]
      if ProcessInfo.processInfo.environment["COLORLIGHTS_V2_QA_SOAK"] == "1",
         session.metricsSequence % 30 == 0 {
        let message = "[SceneSurfaceV2Soak] " +
          "sequence=\(session.metricsSequence) quality=\(session.plan.quality) " +
          "fps=\(effectiveFramesPerSecond) " +
          "deadlines=\(authoredDeadlines) rendered=\(renderedFrames) " +
          "misses=\(deadlineMisses) maxConsecutive=\(maximumConsecutiveMisses) " +
          "scheduled=\(scheduledDeadlines) noChangeDelta=\(noChangeDelta) " +
          "cumulativeDeadlines=\(session.cumulativeAuthoredDeadlines) " +
          "cumulativeRendered=\(session.cumulativeRenderedFrames) " +
          "cumulativeMisses=\(session.cumulativeDeadlineMisses) " +
          "cumulativeMaxConsecutive=" +
          "\(session.cumulativeMaximumConsecutiveDeadlineMisses) " +
          "cadenceTicks=\(session.cadenceTicks) " +
          "cadenceSkipped=\(session.cadenceSkippedPeriods) " +
          "cadenceNoChange=\(session.cadenceNoChangeTicks) " +
          "cadenceRenders=\(session.cadenceRenders) " +
          "signalRenders=\(session.signalRenders) " +
          "signalUpdates=\(session.signalUpdates) " +
          "signalTotalUs=\(session.cumulativeSignalProcessingMicros) " +
          "signalMaxUs=\(session.maximumSignalProcessingMicros) " +
          "maxCadenceLateUs=\(session.maximumCadenceLatenessMicros) " +
          "renderCount=\(session.renderCount) " +
          "renderTotalUs=\(session.cumulativeRenderMicros) " +
          "renderMaxUs=\(session.maximumRenderMicros) " +
          "overBudgetRenders=\(session.overBudgetRenders) " +
          "bufferBackpressure=\(session.pixelBufferBackpressureEvents) " +
          "p95us=\(Self.percentile(samples, fraction: 0.95)) " +
          "p99us=\(Self.percentile(samples, fraction: 0.99)) " +
          "renderer=\(session.rendererAcceptingFrames) " +
          "decoder=\(session.mediaStates.values.filter { $0.decoderCount > 0 }.allSatisfy(\.hasCompleteFrame)) " +
          "complete=\(session.completeFramePresented)"
        Self.qaLogQueue.async { NSLog("%@", message) }
      }
      DispatchQueue.main.async { result(payload) }
    }
  }

  private func beginSteadyStateMetrics(_ session: Session) {
    let now = DispatchTime.now().uptimeNanoseconds
    session.lastMetricsNanos = now
    session.lastMetricsCompleted = session.completed
    session.lastMetricsCadenceNoChangeTicks = session.cadenceNoChangeTicks
    session.lastMetricsCadenceSkippedPeriods = session.cadenceSkippedPeriods
    session.lastMetricsBackpressureEvents = session.pixelBufferBackpressureEvents
    session.metricsSequence = 0
    session.cumulativeAuthoredDeadlines = 0
    session.cumulativeRenderedFrames = 0
    session.cumulativeDeadlineMisses = 0
    session.cumulativeMaximumConsecutiveDeadlineMisses = 0
    session.renderMicros.removeAll(keepingCapacity: true)
    session.consecutiveRenderFailures = 0
    session.maximumConsecutiveRenderFailures = 0
    session.presentationArbiter.resetMetrics()
    session.qualityActivatedAtNanos = now
  }

  private func presentationFramesPerSecond(_ plan: Plan) -> Int {
    sceneRenderV2PresentationFramesPerSecond(
      logicalFramesPerSecond: plan.continuousFramesPerSecond,
      maximumPresentationFramesPerSecond:
        maximumPresentationFramesPerSecond
    )
  }

  /// Retains the exact foreground V2 session as a PiP frame authority.
  ///
  /// A semantic hash is deliberately insufficient when more than one matching
  /// session exists. Refusing ambiguity prevents PiP from borrowing another
  /// scene's decoder or procedural state.
  func retainPictureInPictureSource(
    scenePlan: [String: Any],
    expectedSessionID: String? = nil
  ) -> String? {
    guard
      Set(scenePlan.keys) == Set([
        "sceneDocumentV2", "semanticPlanHash", "registryRevision",
        "qualityPlanHashes",
      ]),
      let document = scenePlan["sceneDocumentV2"] as? [String: Any],
      let semanticPlanHash = scenePlan["semanticPlanHash"] as? String,
      semanticPlanHash == SceneRenderV2ShadowCompiler.semanticPlanHash(
        document: document
      ),
      let registryRevision = scenePlan["registryRevision"] as? String,
      registryRevision == SceneRenderNodeRegistryV1Generated.revision,
      let declaredQualityHashes = Self.stringMap(
        scenePlan["qualityPlanHashes"]
      ),
      declaredQualityHashes == Self.qualityHashes(document)
    else { return nil }
    return queue.sync {
      let matches = sessions.values.filter {
        $0.foregroundAttached &&
          (expectedSessionID == nil || $0.plan.sessionID == expectedSessionID) &&
          $0.completeFramePresented &&
          $0.plan.semanticPlanHash == semanticPlanHash &&
          $0.plan.registryRevision == registryRevision &&
          $0.plan.qualityPlanHashes == declaredQualityHashes
      }
      guard matches.count == 1, let session = matches.first else { return nil }
      session.pictureInPictureRetainCount += 1
      return session.plan.sessionID
    }
  }

  func setPictureInPictureSourcePlaying(
    sessionID: String,
    playing: Bool
  ) {
    preparationGeneration.invalidate()
    queue.async { [weak self] in
      guard
        let self,
        let session = self.sessions[sessionID],
        session.pictureInPictureRetainCount > 0
      else { return }
      session.pictureInPicturePlaying = playing
      self.applyEffectivePlayback(session)
    }
  }

  func copyPictureInPictureFrame(sessionID: String) -> CVPixelBuffer? {
    queue.sync {
      guard
        let session = sessions[sessionID],
        session.pictureInPictureRetainCount > 0,
        session.completeFramePresented
      else { return nil }
      return session.texture.latestPixelBuffer()
    }
  }

  func pictureInPictureFramesPerSecond(sessionID: String) -> Int? {
    queue.sync {
      guard
        let session = sessions[sessionID],
        session.pictureInPictureRetainCount > 0
      else { return nil }
      return session.plan.pictureInPictureFramesPerSecond
    }
  }

  func ensurePictureInPictureMinimumFunctional(
    sessionID: String,
    completion: @escaping (_ accepted: Bool, _ activeSeconds: TimeInterval) -> Void
  ) {
    queue.async { [weak self] in
      guard
        let self,
        let session = self.sessions[sessionID],
        session.pictureInPictureRetainCount > 0,
        let device = self.graphics?.device
      else {
        DispatchQueue.main.async { completion(false, 0) }
        return
      }
      let now = DispatchTime.now().uptimeNanoseconds
      if session.plan.quality == "minimumFunctional" {
        let seconds = TimeInterval(now &- session.qualityActivatedAtNanos) /
          1_000_000_000
        DispatchQueue.main.async { completion(true, seconds) }
        return
      }
      do {
        let buffer = try self.transitionPictureInPictureQuality(
          session,
          quality: "minimumFunctional",
          device: device
        )
        DispatchQueue.main.async {
          session.texture.publish(buffer)
          self.textureRegistry.textureFrameAvailable(session.textureID)
          completion(true, 0)
        }
      } catch {
        DispatchQueue.main.async { completion(false, 0) }
      }
    }
  }

  /// Applies a downward-only quality cap while PiP owns the session.
  /// Foreground remains the sole authority for quality recovery because its
  /// governor observes the complete certified render/deadline window.
  func capPictureInPictureQuality(
    sessionID: String,
    maximumQuality: String,
    completion: @escaping (_ accepted: Bool, _ quality: String) -> Void
  ) {
    queue.async { [weak self] in
      guard
        let self,
        let session = self.sessions[sessionID],
        session.pictureInPictureRetainCount > 0,
        let device = self.graphics?.device,
        let currentIndex = Self.qualityLevels.firstIndex(
          of: session.plan.quality
        ),
        let maximumIndex = Self.qualityLevels.firstIndex(of: maximumQuality)
      else {
        DispatchQueue.main.async { completion(false, "") }
        return
      }
      let targetQuality = Self.qualityLevels[max(currentIndex, maximumIndex)]
      guard targetQuality != session.plan.quality else {
        DispatchQueue.main.async { completion(true, session.plan.quality) }
        return
      }
      do {
        let buffer = try self.transitionPictureInPictureQuality(
          session,
          quality: targetQuality,
          device: device
        )
        DispatchQueue.main.async {
          session.texture.publish(buffer)
          self.textureRegistry.textureFrameAvailable(session.textureID)
          completion(true, targetQuality)
        }
      } catch {
        DispatchQueue.main.async { completion(false, session.plan.quality) }
      }
    }
  }

  private func transitionPictureInPictureQuality(
    _ session: Session,
    quality: String,
    device: MTLDevice
  ) throws -> CVPixelBuffer {
    var next = session.plan
    next.quality = quality
    let buffer = try renderFrame(
      session: session,
      plan: next,
      device: device,
      strobeFrames: strobeFrames(session)
    )
    stopCadence(session)
    session.qualityActivatedAtNanos = DispatchTime.now().uptimeNanoseconds
    session.plan = next
    rebindStrobeStates(session, plan: next)
    rebindMediaStates(session, plan: next)
    rebindRadialProfileStates(session, plan: next)
    startCadenceIfNeeded(session)
    return buffer
  }

  func releasePictureInPictureSource(
    sessionID: String,
    completion: (() -> Void)? = nil
  ) {
    preparationGeneration.invalidate()
    queue.async { [weak self] in
      guard
        let self,
        let session = self.sessions[sessionID],
        session.pictureInPictureRetainCount > 0
      else {
        DispatchQueue.main.async { completion?() }
        return
      }
      session.pictureInPictureRetainCount -= 1
      if session.pictureInPictureRetainCount == 0 {
        session.pictureInPicturePlaying = false
      }
      self.applyEffectivePlayback(session)
      guard
        session.pictureInPictureRetainCount == 0,
        !session.foregroundAttached
      else {
        DispatchQueue.main.async { completion?() }
        return
      }
      self.sessions.removeValue(forKey: sessionID)
      self.tearDownPresentation(session)
      session.mediaStates.values.forEach { $0.tearDown() }
      session.installedProgramStates.values.forEach { $0.tearDown() }
      let unregister = session.flutterTextureRegistered
      session.flutterTextureRegistered = false
      DispatchQueue.main.async { [textureRegistry = self.textureRegistry] in
        if unregister {
          textureRegistry.unregisterTexture(session.textureID)
        }
        completion?()
      }
    }
  }

  /// An ACK barrier includes any earlier asynchronous PiP release and texture
  /// unregister submitted to the main queue. It never creates or borrows a graph.
  func acknowledgePictureInPictureCleanup(completion: @escaping () -> Void) {
    queue.async { DispatchQueue.main.async(execute: completion) }
  }

  func detach(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      Set(arguments.keys) == Set(["sessionId"]),
      let sessionID = arguments["sessionId"] as? String
    else {
      result(error("detach_v2_invalid", "Invalid V2 detach."))
      return
    }
    preparationGeneration.invalidate()
    queue.async { [weak self] in
      guard let self else { return }
      guard let session = self.sessions[sessionID] else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      session.foregroundAttached = false
      session.foregroundPlaying = false
      self.applyEffectivePlayback(session)
      let retainedForPictureInPicture = session.pictureInPictureRetainCount > 0
      if !retainedForPictureInPicture {
        self.sessions.removeValue(forKey: sessionID)
        self.tearDownPresentation(session)
        session.mediaStates.values.forEach { $0.tearDown() }
        session.installedProgramStates.values.forEach { $0.tearDown() }
      }
      let unregister = !retainedForPictureInPicture && session.flutterTextureRegistered
      if unregister { session.flutterTextureRegistered = false }
      DispatchQueue.main.async {
        if unregister {
          self.textureRegistry.unregisterTexture(session.textureID)
        }
        result(nil)
      }
    }
  }

  func shutdown() {
    preparationGeneration.invalidate()
    queue.sync {
      let active = Array(sessions.values)
      active.forEach {
        tearDownPresentation($0)
        $0.mediaStates.values.forEach { $0.tearDown() }
        $0.installedProgramStates.values.forEach { $0.tearDown() }
      }
      sessions.removeAll()
      DispatchQueue.main.async { [textureRegistry] in
        active.forEach { textureRegistry.unregisterTexture($0.textureID) }
      }
    }
  }

  private func observed(_ session: Session) -> [String: Any] {
    [
      "rendererRevision": "native_scene_surface_v2_ios_graph_21",
      "registryRevision": session.plan.registryRevision,
      "semanticPlanHash": session.plan.semanticPlanHash,
      "qualityPlanHash": session.plan.qualityPlanHash,
      "capabilityFingerprint": capabilityFingerprint,
      "graphicsApi": "metal",
      "backendClass": "scene_surface_metal_ci_gpu",
      "quality": session.plan.quality,
      "gpuSubmitted": max(1, session.submitted),
      "gpuCompleted": max(1, session.completed),
      "cpuReference": 0,
      "fallback": 0,
      "failureCount": 0,
    ]
  }

  private var capabilityFingerprint: String {
    let source = [
      "native_scene_surface_v2_ios_graph_21",
      SceneRenderNodeRegistryV1Generated.revision,
      SHA256.hash(
        data: Data(SceneRenderNodeRegistryV1Generated.canonicalJSON.utf8)
      ).map { String(format: "%02x", $0) }.joined(),
      graphics?.device.name ?? "unavailable",
    ].joined(separator: "|")
    return SHA256.hash(data: Data(source.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private var capabilityClass: String {
    guard let device = graphics?.device else {
      return sceneRenderV2MetalCapabilityClass(
        SceneRenderV2MetalCapabilityDescriptor(
          deviceName: "unavailable",
          maxThreadsWidth: 0,
          maxThreadsHeight: 0,
          maxThreadsDepth: 0,
          maxThreadgroupMemoryLength: 0,
          maxBufferLength: 0,
          readWriteTextureTier: 0,
          argumentBuffersTier: 0
        )
      )
    }
    let threads = device.maxThreadsPerThreadgroup
    return sceneRenderV2MetalCapabilityClass(
      SceneRenderV2MetalCapabilityDescriptor(
        deviceName: device.name,
        maxThreadsWidth: threads.width,
        maxThreadsHeight: threads.height,
        maxThreadsDepth: threads.depth,
        maxThreadgroupMemoryLength: device.maxThreadgroupMemoryLength,
        maxBufferLength: UInt64(device.maxBufferLength),
        readWriteTextureTier: Int(device.readWriteTextureSupport.rawValue),
        argumentBuffersTier: Int(device.argumentBuffersSupport.rawValue)
      )
    )
  }

  private func renderFrame(
    session: Session,
    plan: Plan,
    device: MTLDevice,
    strobeFrames: [String: StrobeFrame],
    imageReactiveStates: [String: SceneRenderV2NaturalReactiveLightState]? = nil,
    mediaStates: [String: MediaState]? = nil,
    radialProfileStates: [String: SceneRenderV2RadialProfileState]? = nil,
    radialWarpStates: [String: SceneRenderV2RadialWarpState]? = nil,
    snowfallStates: [String: SceneRenderV2SnowfallState]? = nil,
    paintedStarlightStates: [String: SceneRenderV2PaintedStarlightState]? = nil,
    magicStarsStates: [String: SceneRenderV2MagicStarsState]? = nil,
    magicMoonStates: [String: SceneRenderV2MagicMoonState]? = nil,
    radiantEmissionStates: [String: SceneRenderV2RadiantEmissionState]? = nil,
    rainbowWaterfallStates: [String: SceneRenderV2RainbowWaterfallState]? = nil,
    neonPulseStates: [String: SceneRenderV2NeonPulseState]? = nil,
    embeddedScreenStates: [String: SceneRenderV2EmbeddedScreenState]? = nil,
    waveformStates: [String: SceneRenderV2WaveformState]? = nil,
    installedProgramStates: [String: SceneRenderV2InstalledProgramState]? = nil
  ) throws -> CVPixelBuffer {
    session.submitted += 1
    let started = DispatchTime.now().uptimeNanoseconds
    do {
      let buffer = try render(
        session: session,
        plan: plan,
        device: device,
        strobeFrames: strobeFrames,
        imageReactiveStates: imageReactiveStates ?? session.imageReactiveStates,
        mediaStates: mediaStates ?? session.mediaStates,
        radialProfileStates: radialProfileStates ?? session.radialProfileStates,
        radialWarpStates: radialWarpStates ?? session.radialWarpStates,
        snowfallStates: snowfallStates ?? session.snowfallStates,
        paintedStarlightStates:
          paintedStarlightStates ?? session.paintedStarlightStates,
        magicStarsStates: magicStarsStates ?? session.magicStarsStates,
        magicMoonStates: magicMoonStates ?? session.magicMoonStates,
        radiantEmissionStates:
          radiantEmissionStates ?? session.radiantEmissionStates,
        rainbowWaterfallStates:
          rainbowWaterfallStates ?? session.rainbowWaterfallStates,
        neonPulseStates: neonPulseStates ?? session.neonPulseStates,
        embeddedScreenStates:
          embeddedScreenStates ?? session.embeddedScreenStates,
        waveformStates: waveformStates ?? session.waveformStates,
        installedProgramStates:
          installedProgramStates ?? session.installedProgramStates
      )
      let elapsed = DispatchTime.now().uptimeNanoseconds &- started
      let elapsedMicros = max(0, Int(elapsed / 1_000))
      session.completed += 1
      session.renderCount += 1
      session.cumulativeRenderMicros += elapsedMicros
      session.maximumRenderMicros = max(session.maximumRenderMicros, elapsedMicros)
      let renderBudgetMicros = 1_000_000 /
        presentationFramesPerSecond(session.plan)
      if elapsedMicros > renderBudgetMicros { session.overBudgetRenders += 1 }
      session.renderMicros.append(elapsedMicros)
      if session.renderMicros.count > 256 {
        session.renderMicros.removeFirst(session.renderMicros.count - 256)
      }
      session.completeFramePresented = true
      session.rendererAcceptingFrames = true
      session.consecutiveRenderFailures = 0
      return buffer
    } catch let runtimeError as RuntimeError where runtimeError.isBackpressure {
      session.submitted = max(0, session.submitted - 1)
      throw runtimeError
    } catch {
      session.rendererAcceptingFrames = false
      session.consecutiveRenderFailures += 1
      session.maximumConsecutiveRenderFailures = max(
        session.maximumConsecutiveRenderFailures,
        session.consecutiveRenderFailures
      )
      throw error
    }
  }

  private func render(
    session: Session,
    plan: Plan,
    device: MTLDevice,
    strobeFrames: [String: StrobeFrame] = [:],
    imageReactiveStates: [String: SceneRenderV2NaturalReactiveLightState] = [:],
    mediaStates: [String: MediaState] = [:],
    radialProfileStates: [String: SceneRenderV2RadialProfileState] = [:],
    radialWarpStates: [String: SceneRenderV2RadialWarpState] = [:],
    snowfallStates: [String: SceneRenderV2SnowfallState] = [:],
    paintedStarlightStates: [String: SceneRenderV2PaintedStarlightState] = [:],
    magicStarsStates: [String: SceneRenderV2MagicStarsState] = [:],
    magicMoonStates: [String: SceneRenderV2MagicMoonState] = [:],
    radiantEmissionStates: [String: SceneRenderV2RadiantEmissionState] = [:],
    rainbowWaterfallStates: [String: SceneRenderV2RainbowWaterfallState] = [:],
    neonPulseStates: [String: SceneRenderV2NeonPulseState] = [:],
    embeddedScreenStates: [String: SceneRenderV2EmbeddedScreenState] = [:],
    waveformStates: [String: SceneRenderV2WaveformState] = [:],
    installedProgramStates: [String: SceneRenderV2InstalledProgramState] = [:]
  ) throws -> CVPixelBuffer {
    guard let graphics else {
      throw RuntimeError("graphics_context_unavailable")
    }
    let poolKey = BufferPoolKey(width: plan.pixelWidth, height: plan.pixelHeight)
    let pool: CVPixelBufferPool
    let createdPool: Bool
    if let existing = session.bufferPools[poolKey] {
      pool = existing
      createdPool = false
    } else {
      let attributes: [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey: plan.pixelWidth,
        kCVPixelBufferHeightKey: plan.pixelHeight,
        kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
        kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      ]
      var candidate: CVPixelBufferPool?
      let status = CVPixelBufferPoolCreate(
        kCFAllocatorDefault,
        [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary,
        attributes as CFDictionary,
        &candidate
      )
      guard status == kCVReturnSuccess, let candidate else {
        throw RuntimeError("pixel_buffer_pool_failed")
      }
      session.bufferPools[poolKey] = candidate
      pool = candidate
      createdPool = true
    }
    var buffer: CVPixelBuffer?
    let allocationAttributes = [
      kCVPixelBufferPoolAllocationThresholdKey:
        Self.maximumPixelBuffersPerOutputPool,
    ] as CFDictionary
    let allocationStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
        kCFAllocatorDefault,
        pool,
        allocationAttributes,
        &buffer
      )
    if allocationStatus == kCVReturnWouldExceedAllocationThreshold {
      throw RuntimeError("pixel_buffer_backpressure")
    }
    guard allocationStatus == kCVReturnSuccess, let buffer else {
      if createdPool { session.bufferPools.removeValue(forKey: poolKey) }
      throw RuntimeError("pixel_buffer_failed")
    }
    let target = CGRect(x: 0, y: 0, width: plan.pixelWidth, height: plan.pixelHeight)
    var composed = CIImage(
      color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
    ).cropped(to: target)
    for node in plan.nodes {
      let renderedNode: CIImage
      switch node {
      case .solidColor(_, let opacity, _):
        renderedNode = CIImage(
          color: CIColor(red: 0, green: 0, blue: 0, alpha: opacity)
        ).cropped(to: target)
      case .image(let layer, _):
        let width = target.width * layer.width
        let height = target.height * layer.height
        let layerRect = CGRect(
          x: target.midX - width * 0.5 + target.width * layer.offsetX,
          y: target.midY - height * 0.5 - target.height * layer.offsetY,
          width: width,
          height: height
        )
        let source = imageReactiveStates[layer.id]?.apply(to: layer.source) ?? layer.source
        var rendered = Self.aspectFill(source, targetRect: layerRect)
        let center = CGPoint(x: layerRect.midX, y: layerRect.midY)
        var affine = CGAffineTransform(translationX: center.x, y: center.y)
        affine = affine.rotated(by: -layer.rotation)
        affine = affine.scaledBy(
          x: layer.flipped ? -layer.scale : layer.scale,
          y: layer.scale
        )
        affine = affine.translatedBy(x: -center.x, y: -center.y)
        rendered = rendered.transformed(by: affine).cropped(to: target)
        if layer.opacity < 0.999_999 {
          rendered = rendered.applyingFilter(
            "CIColorMatrix",
            parameters: [
              "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity),
            ]
          )
        }
        renderedNode = rendered
      case .media(let layer):
        guard let source = mediaStates[layer.id]?.currentImage() else {
          throw RuntimeError("media_frame_missing")
        }
        renderedNode = Self.renderMediaLayer(layer, source: source, target: target)
      case .strobe(let layer, _):
        guard let strobeFrame = strobeFrames[layer.id] else {
          throw RuntimeError("strobe_frame_missing")
        }
        guard let rendered = strobeFrame.render(target: target, opacity: layer.opacity) else {
          throw RuntimeError("strobe_frame_render_failed")
        }
        renderedNode = rendered
      case .radialProfile(let layer):
        guard let state = radialProfileStates[layer.id] else {
          throw RuntimeError("radial_profile_state_missing")
        }
        renderedNode = try Self.renderRadialProfileLayer(
          layer,
          state: state,
          target: target
        )
      case .radialWarp(let layer):
        guard let state = radialWarpStates[layer.id] else {
          throw RuntimeError("radial_warp_state_missing")
        }
        renderedNode = try Self.renderRadialWarpLayer(
          graphics: graphics,
          layer,
          state: state,
          quality: plan.quality,
          target: target,
          device: device
        )
      case .snowfall(let layer):
        guard let state = snowfallStates[layer.id] else {
          throw RuntimeError("snowfall_state_missing")
        }
        renderedNode = try Self.renderSnowfallLayer(
          graphics: graphics,
          layer,
          state: state,
          quality: plan.quality,
          pointScale: Float(
            plan.devicePixelRatio * (layer.renderScales[plan.quality] ?? 1)
          ),
          target: target
        )
      case .paintedStarlight(let layer):
        guard let state = paintedStarlightStates[layer.id] else {
          throw RuntimeError("painted_starlight_state_missing")
        }
        renderedNode = try Self.renderPaintedStarlightLayer(
          graphics: graphics,
          layer,
          state: state,
          quality: plan.quality,
          target: target
        )
      case .magicStars(let layer):
        guard let state = magicStarsStates[layer.id] else {
          throw RuntimeError("magic_stars_state_missing")
        }
        renderedNode = try Self.renderMagicStarsLayer(
          graphics: graphics,
          layer,
          state: state,
          quality: plan.quality,
          pointScale: Float(
            plan.devicePixelRatio * (layer.renderScales[plan.quality] ?? 1)
          ),
          target: target
        )
      case .blueSky(let layer):
        renderedNode = Self.renderBlueSkyLayer(layer, target: target)
      case .magicMoon(let layer):
        guard let state = magicMoonStates[layer.id] else {
          throw RuntimeError("magic_moon_state_missing")
        }
        renderedNode = try Self.renderMagicMoonLayer(
          layer,
          state: state,
          target: target
        )
      case .radiantEmission(let layer):
        guard let state = radiantEmissionStates[layer.id] else {
          throw RuntimeError("radiant_emission_state_missing")
        }
        renderedNode = try Self.renderRadiantEmissionLayer(
          layer,
          state: state,
          quality: plan.quality,
          target: target
        )
      case .rainbowWaterfall(let layer):
        guard let state = rainbowWaterfallStates[layer.id] else {
          throw RuntimeError("rainbow_waterfall_state_missing")
        }
        renderedNode = try Self.renderRainbowWaterfallLayer(
          layer,
          state: state,
          target: target
        )
      case .neonPulse(let layer):
        guard let state = neonPulseStates[layer.id] else {
          throw RuntimeError("neon_pulse_state_missing")
        }
        renderedNode = try Self.renderNeonPulseLayer(
          graphics: graphics,
          layer,
          state: state,
          quality: plan.quality,
          pointScale: Float(
            plan.devicePixelRatio * (layer.renderScales[plan.quality] ?? 1)
          ),
          target: target
        )
      case .embeddedScreen(let layer):
        guard let state = embeddedScreenStates[layer.id] else {
          throw RuntimeError("embedded_screen_state_missing")
        }
        renderedNode = try Self.renderEmbeddedScreenLayer(
          graphics: graphics,
          layer,
          state: state,
          quality: plan.quality,
          target: target
        )
      case .waveform(let layer):
        guard let state = waveformStates[layer.id] else {
          throw RuntimeError("waveform_state_missing")
        }
        renderedNode = try Self.renderWaveformLayer(
          graphics: graphics,
          layer,
          state: state,
          quality: plan.quality,
          pointScale: Float(
            plan.devicePixelRatio * (layer.renderScales[plan.quality] ?? 1)
          ),
          target: target
        )
      case .installedProgram(let layer):
        guard
          let state = installedProgramStates[layer.id],
          let image = state.image(layer: layer, targetRect: target)
        else {
          throw RuntimeError("installed_program_frame_missing")
        }
        renderedNode = image
      }
      let compositor = switch node {
      case .radiantEmission: "CIAdditionCompositing"
      default: "CISourceOverCompositing"
      }
      composed = renderedNode.applyingFilter(
        compositor,
        parameters: [kCIInputBackgroundImageKey: composed]
      ).cropped(to: target)
    }
    if let filter = plan.filter {
      guard
        let kernel = Self.filterGradeKernel,
        let filtered = kernel.apply(
          extent: target,
          arguments: [
            composed,
            CIVector(x: target.origin.x, y: target.origin.y),
            CIVector(x: target.width, y: target.height),
            filter.intensity,
            filter.exposure,
            filter.contrast,
            filter.saturation,
            filter.vibrance,
            filter.temperature,
            filter.tint,
            filter.blackLift,
            filter.highlightRolloff,
            filter.shadowDepth,
            filter.midtoneBalance,
            filter.colorDensity,
            filter.cyanPresence,
            filter.magentaPresence,
            filter.goldPresence,
            CIVector(
              x: filter.shadows.red,
              y: filter.shadows.green,
              z: filter.shadows.blue
            ),
            filter.shadows.amount,
            CIVector(
              x: filter.midtones.red,
              y: filter.midtones.green,
              z: filter.midtones.blue
            ),
            filter.midtones.amount,
            CIVector(
              x: filter.highlights.red,
              y: filter.highlights.green,
              z: filter.highlights.blue
            ),
            filter.highlights.amount,
            filter.vignette,
            filter.vignetteSoftness,
          ]
        )
      else { throw RuntimeError("filter_grade_unavailable") }
      composed = filtered.cropped(to: target)
    }
    let destination = CIRenderDestination(pixelBuffer: buffer)
    destination.colorSpace = Self.outputColorSpace
    do {
      let task = try graphics.ciContext.startTask(
        toRender: composed,
        from: target,
        to: destination,
        at: .zero
      )
      try task.waitUntilCompleted()
    } catch {
      if createdPool { session.bufferPools.removeValue(forKey: poolKey) }
      throw error
    }
    session.bufferPools = [poolKey: pool]
    _ = device
    return buffer
  }

  private func parseAttach(_ value: Any?) -> Plan? {
    guard
      let envelope = value as? [String: Any],
      Set(envelope.keys) == Set([
        "sessionId", "sceneDocumentV2", "semanticPlanHash", "qualityPlanHash",
        "registryRevision", "initialQuality", "continuityState", "width",
        "height", "devicePixelRatio", "playing", "resolvedResourcePathsById",
      ]),
      let sessionID = envelope["sessionId"] as? String,
      validToken(sessionID),
      let document = envelope["sceneDocumentV2"] as? [String: Any],
      let semanticPlanHash = envelope["semanticPlanHash"] as? String,
      SceneRenderV2ShadowCompiler.semanticPlanHash(document: document) ==
        semanticPlanHash,
      let registryRevision = envelope["registryRevision"] as? String,
      registryRevision == SceneRenderNodeRegistryV1Generated.revision,
      let shadow = SceneRenderV2ShadowCompiler.preflight(
        arguments: [
          "sceneDocumentV2": document,
          "semanticPlanHash": semanticPlanHash,
          "registryRevision": registryRevision,
        ],
        metalAvailable: graphics != nil
      ),
      shadow.issueCodes == ["v2_runtime_not_installed"],
      let quality = envelope["initialQuality"] as? String,
      Self.qualityLevels.contains(quality),
      let suppliedQualityHash = envelope["qualityPlanHash"] as? String,
      let qualityPlanHashes = Self.qualityHashes(document),
      qualityPlanHashes[quality] == suppliedQualityHash,
      let continuity = envelope["continuityState"] as? [String: Any],
      Self.validContinuity(continuity),
      let mediaPtsMicros = Self.integer(
        continuity["mediaPtsMicros"],
        minimum: 0
      ),
      let sessionSeedValue = Self.integer(
        continuity["sessionSeed"],
        minimum: 0
      ),
      let width = Self.finitePositive(envelope["width"]),
      let height = Self.finitePositive(envelope["height"]),
      let scale = Self.finitePositive(envelope["devicePixelRatio"]),
      let playing = envelope["playing"] as? Bool,
      let resolvedPaths = Self.stringMap(envelope["resolvedResourcePathsById"]),
      let materialized = Self.materializeResources(
        document,
        resolvedPaths: resolvedPaths
      ),
      let parsed = Self.parseDocument(materialized, loadImage: true)
    else {
      return nil
    }
    return Plan(
      sessionID: sessionID,
      document: document,
      semanticPlanHash: semanticPlanHash,
      qualityPlanHashes: qualityPlanHashes,
      registryRevision: registryRevision,
      quality: quality,
      width: width,
      height: height,
      devicePixelRatio: scale,
      playing: playing,
      mediaPtsMicros: mediaPtsMicros,
      sessionSeed: UInt32(sessionSeedValue),
      nodes: parsed.nodes,
      filter: parsed.filter
    )
  }

  /// Binds canonical HTTPS resources to local files without changing the
  /// semantic document used for cross-platform hashes and receipts.
  private static func materializeResources(
    _ document: [String: Any],
    resolvedPaths: [String: String]?
  ) -> [String: Any]? {
    guard let rawLayers = document["layers"] as? [[String: Any]] else {
      return nil
    }
    var requiredIDs = Set<String>()
    var layers = [[String: Any]]()
    for rawLayer in rawLayers {
      guard var node = rawLayer["node"] as? [String: Any],
            let rawSlots = node["resourceSlots"] as? [[String: Any]] else {
        return nil
      }
      var slots = [[String: Any]]()
      for rawSlot in rawSlots {
        guard let uri = rawSlot["uri"] as? String else {
          slots.append(rawSlot)
          continue
        }
        guard
          Self.isSecureRemoteResourceURI(uri),
          let resourceID = rawSlot["resourceId"] as? String,
          validToken(resourceID),
          requiredIDs.insert(resourceID).inserted
        else { return nil }
        let path = resolvedPaths?[resourceID] ?? "/v2-preflight/\(resourceID)"
        guard Self.isCanonicalLocalResourcePath(path),
              resolvedPaths == nil || !path.hasPrefix("/v2-preflight/") else {
          return nil
        }
        var slot = rawSlot
        slot.removeValue(forKey: "uri")
        slot["path"] = path
        slots.append(slot)
      }
      node["resourceSlots"] = slots
      var layer = rawLayer
      layer["node"] = node
      layers.append(layer)
    }
    if let resolvedPaths, Set(resolvedPaths.keys) != requiredIDs { return nil }
    var result = document
    result["layers"] = layers
    return result
  }

  private static func isSecureRemoteResourceURI(_ value: String) -> Bool {
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.contains("\0"),
          let components = URLComponents(string: value),
          components.scheme?.lowercased() == "https",
          let host = components.host, !host.isEmpty,
          components.user == nil,
          components.password == nil,
          components.fragment == nil else { return false }
    return true
  }

  private static func isCanonicalLocalResourcePath(_ value: String) -> Bool {
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          value.hasPrefix("/"), !value.hasPrefix("//"),
          !value.contains("//"), !value.contains("\0") else { return false }
    return !value.split(separator: "/", omittingEmptySubsequences: false)
      .contains { $0 == "." || $0 == ".." }
  }

  private static func qualityHashes(_ document: [String: Any]) -> [String: String]? {
    var result = [String: String]()
    for quality in Self.qualityLevels {
      guard let hash = SceneRenderV2ShadowCompiler.qualityPlanHash(
        document: document,
        quality: quality
      ) else { return nil }
      result[quality] = hash
    }
    return result
  }

  private static func stringMap(_ value: Any?) -> [String: String]? {
    guard let raw = value as? [String: Any] else { return nil }
    var result = [String: String]()
    for (key, value) in raw {
      guard let string = value as? String else { return nil }
      result[key] = string
    }
    return result
  }

  private static func parseDocument(
    _ document: [String: Any],
    loadImage: Bool
  ) -> ParsedDocument? {
    let requiredDocumentKeys = Set(["schemaVersion", "sceneId", "layers"])
    let allowedDocumentKeys = requiredDocumentKeys.union(["filterNode"])
    guard
      Set(document.keys).isSubset(of: allowedDocumentKeys),
      requiredDocumentKeys.isSubset(of: Set(document.keys)),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      !layers.isEmpty,
      layers.count <= 12
    else { return nil }
    var result = [GraphNode]()
    var layerIDs = Set<String>()
    for layer in layers {
      guard let layerID = layer["id"] as? String,
            validToken(layerID), layerIDs.insert(layerID).inserted else {
        return nil
      }
      let single: [String: Any] = [
        "schemaVersion": 2,
        "sceneId": sceneID,
        "layers": [layer],
      ]
      if let solid = Self.parseDeepVoidDocument(single) {
        result.append(solid)
        continue
      }
      if let image = Self.parseImageDocument(single, loadImage: loadImage)?.first {
        result.append(.image(image, renderScales: Self.imageRenderScales))
        continue
      }
      if let media = Self.parseMediaDocument(single, resolveResource: loadImage) {
        result.append(.media(media))
        continue
      }
      if let strobe = Self.parseStrobeDocument(single) {
        result.append(.strobe(strobe, renderScales: Self.strobeRenderScales))
        continue
      }
      if let radialWarp = Self.parseRadialWarpDocument(single) {
        result.append(.radialWarp(radialWarp))
        continue
      }
      if let snowfall = Self.parseSnowfallDocument(single) {
        result.append(.snowfall(snowfall))
        continue
      }
      if let magicStars = Self.parseMagicStarsDocument(single) {
        result.append(.magicStars(magicStars))
        continue
      }
      if let blueSky = Self.parseBlueSkyDocument(single) {
        result.append(.blueSky(blueSky))
        continue
      }
      if let magicMoon = Self.parseMagicMoonDocument(single, loadImage: loadImage) {
        result.append(.magicMoon(magicMoon))
        continue
      }
      if let radiantEmission = Self.parseRadiantEmissionDocument(single) {
        result.append(.radiantEmission(radiantEmission))
        continue
      }
      if let rainbowWaterfall = Self.parseRainbowWaterfallDocument(single) {
        result.append(.rainbowWaterfall(rainbowWaterfall))
        continue
      }
      if let neonPulse = Self.parseNeonPulseDocument(single) {
        result.append(.neonPulse(neonPulse))
        continue
      }
      if let embeddedScreen = Self.parseEmbeddedScreenDocument(
        single,
        loadImage: loadImage
      ) {
        result.append(.embeddedScreen(embeddedScreen))
        continue
      }
      if let waveform = Self.parseWaveformDocument(single) {
        result.append(.waveform(waveform))
        continue
      }
      if let installedProgram = Self.parseInstalledProgramDocument(single) {
        result.append(.installedProgram(installedProgram))
        continue
      }
      if let paintedStarlight = Self.parsePaintedStarlightDocument(single) {
        result.append(.paintedStarlight(paintedStarlight))
        continue
      }
      if let radialProfile = Self.parseRadialProfileDocument(
        single,
        resolveResource: loadImage
      ) {
        result.append(.radialProfile(radialProfile))
        continue
      }
      return nil
    }
    let filter: FilterGrade?
    if document.keys.contains("filterNode") {
      guard
        Self.filterGradeKernel != nil,
        let parsed = Self.parseFilterGrade(document["filterNode"])
      else { return nil }
      filter = parsed
    } else {
      filter = nil
    }
    return ParsedDocument(nodes: result, filter: filter)
  }

  private static func parseDeepVoidDocument(_ document: [String: Any]) -> GraphNode? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layer["role"] as? String == "background",
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      ["preferred", "staticContent"].contains(
        layer["frameRateBinding"] as? String ?? ""
      ),
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 1,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.identityTransform(layer["transform"]),
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      let node = layer["node"] as? [String: Any],
      node["nodeType"] as? String == "program.installed",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "atomicParameters",
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      (node["signalBindings"] as? [Any])?.isEmpty == true,
      let parameters = node["parameters"] as? [String: Any],
      parameters["programId"] as? String == "deep_void_v1",
      parameters["audioReactive"] as? Bool == false,
      Set(parameters.keys).isSubset(of: Set([
        "programId", "seed", "palette", "parameters", "audioReactive", "effect",
        "runtime",
      ])),
      parameters["runtime"] == nil || Self.validStaticRuntimeMetadata(
        parameters["runtime"],
        role: "background"
      ),
      Self.validStaticProgramVariants(node["qualityVariants"])
    else { return nil }
    return .solidColor(
      id: layerID,
      opacity: opacity,
      renderScales: Self.imageRenderScales
    )
  }

  private static func validStaticRuntimeMetadata(
    _ value: Any?,
    role expectedRole: String
  ) -> Bool {
    guard
      let runtime = value as? [String: Any],
      Set(runtime.keys) == Set([
        "costUnits", "priority", "role", "updatePolicy",
      ]),
      let costUnits = Self.finite(runtime["costUnits"]),
      costUnits >= 0,
      costUnits <= 100,
      let priority = (runtime["priority"] as? NSNumber)?.intValue,
      priority >= -1_000,
      priority <= 1_000,
      runtime["role"] as? String == expectedRole,
      runtime["updatePolicy"] as? String == "static"
    else {
      return false
    }
    return true
  }

  private static func validStaticProgramVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any] else { return false }
      return variant["level"] as? String == quality &&
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true &&
        Self.number(variant["renderScale"], equals: Self.imageRenderScales[quality]!) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue == 1 &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseRadialWarpDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2RadialWarpLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      ["background", "overlay"].contains(layer["role"] as? String ?? ""),
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 30,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.identityTransform(layer["transform"]),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.spriteParticles",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      Self.validStrobeBindings(node["signalBindings"], required: true),
      Self.validRadialWarpParameters(node["parameters"]),
      Self.validRadialWarpVariants(node["qualityVariants"])
    else { return nil }
    return SceneRenderV2RadialWarpLayer(
      id: layerID,
      opacity: opacity,
      renderScales: Self.radialWarpRenderScales,
      framesPerSecondByQuality: Self.radialWarpFramesPerSecond,
      particleCountsByQuality: Self.radialWarpParticleCounts,
      bloomByQuality: Self.radialWarpBloom
    )
  }

  private static func validRadialWarpParameters(_ value: Any?) -> Bool {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys) == Set([
        "programId", "seed", "count", "enableBloom", "palette", "parameters",
        "audioReactive",
      ]),
      parameters["programId"] as? String == "radial_warp_field_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 742_901,
      (parameters["count"] as? NSNumber)?.intValue == 460,
      parameters["enableBloom"] as? Bool == true,
      parameters["audioReactive"] as? Bool == true,
      let palette = parameters["palette"] as? [NSNumber],
      palette.map(\.int64Value) == Self.radialWarpPalette,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "framesPerSecond", "travelSpeed", "streakScale", "centerX",
        "centerY", "glowScale", "flowResponse", "bassResponse", "sparkResponse",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      (recipe["framesPerSecond"] as? NSNumber)?.intValue == 30,
      Self.number(recipe["travelSpeed"], equals: 0.11),
      Self.number(recipe["streakScale"], equals: 1),
      Self.number(recipe["centerX"], equals: 0.5),
      Self.number(recipe["centerY"], equals: 0.5),
      Self.number(recipe["glowScale"], equals: 1),
      Self.number(recipe["flowResponse"], equals: 0.68),
      Self.number(recipe["bassResponse"], equals: 0.58),
      Self.number(recipe["sparkResponse"], equals: 0.46)
    else { return false }
    return true
  }

  private static func validRadialWarpVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any],
            let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["count", "enableBloom"]) &&
        (overrides["count"] as? NSNumber)?.intValue ==
          Self.radialWarpParticleCounts[quality] &&
        overrides["enableBloom"] as? Bool == Self.radialWarpBloom[quality] &&
        Self.number(variant["renderScale"], equals: Self.radialWarpRenderScales[quality]!) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.radialWarpFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseSnowfallDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2SnowfallLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layer["role"] as? String == "overlay",
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 30,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.identityTransform(layer["transform"]),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.spriteParticles",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      (node["signalBindings"] as? [Any])?.isEmpty == true,
      let particleData = Self.validSnowfallParameters(node["parameters"]),
      Self.validSnowfallVariants(node["qualityVariants"])
    else { return nil }
    return SceneRenderV2SnowfallLayer(
      id: layerID,
      opacity: opacity,
      particleData: particleData,
      renderScales: Self.snowfallRenderScales,
      framesPerSecondByQuality: Self.snowfallFramesPerSecond,
      particleCountsByQuality: Self.snowfallParticleCounts
    )
  }

  private static func validSnowfallParameters(_ value: Any?) -> Data? {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys) == Set([
        "programId", "seed", "count", "enableBloom", "parameters", "audioReactive",
      ]),
      parameters["programId"] as? String == "winter_snowfall_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 82_127,
      (parameters["count"] as? NSNumber)?.intValue == 144,
      parameters["enableBloom"] as? Bool == false,
      parameters["audioReactive"] as? Bool == false,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "sourceFramesPerSecond", "particleCount",
        "particleStrideBytes", "particleDataBase64", "strokeWidths", "colors",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 30,
      (recipe["particleCount"] as? NSNumber)?.intValue == 144,
      (recipe["particleStrideBytes"] as? NSNumber)?.intValue == 36,
      let strokes = recipe["strokeWidths"] as? [NSNumber],
      strokes.map(\.doubleValue) == Self.snowfallStrokeWidths,
      let colors = recipe["colors"] as? [NSNumber],
      colors.map(\.int64Value) == Self.snowfallColors,
      let encoded = recipe["particleDataBase64"] as? String,
      let data = Data(base64Encoded: encoded, options: []),
      data.count == 144 * 36,
      Self.validSnowfallParticles(data)
    else { return nil }
    return data
  }

  private static func validSnowfallParticles(_ data: Data) -> Bool {
    let bytes = [UInt8](data)
    func uint32(_ offset: Int) -> UInt32 {
      UInt32(bytes[offset]) |
        UInt32(bytes[offset + 1]) << 8 |
        UInt32(bytes[offset + 2]) << 16 |
        UInt32(bytes[offset + 3]) << 24
    }
    func float32(_ offset: Int) -> Float { Float(bitPattern: uint32(offset)) }
    for index in 0..<144 {
      let offset = index * 36
      let values = (0..<8).map { float32(offset + $0 * 4) }
      guard values.allSatisfy(\.isFinite) else { return false }
      let band = uint32(offset + 32)
      guard
        values[0] >= 0, values[0] <= 1,
        values[1] >= 0, values[1] <= values[7],
        values[2] >= 0.018, values[2] <= 0.086,
        values[3] >= 0.002, values[3] <= 0.031,
        values[4] >= 0.24, values[4] <= 0.70,
        values[6] >= -0.081, values[6] <= 1.04,
        values[7] >= 0.48, values[7] <= 1.161,
        band <= 3
      else { return false }
    }
    return true
  }

  private static func validSnowfallVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any],
            Set(variant.keys) == Set([
              "level", "parameterOverrides", "renderScale", "framesPerSecond",
              "resourceOverrides",
            ]),
            let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["count", "enableBloom"]) &&
        (overrides["count"] as? NSNumber)?.intValue ==
          Self.snowfallParticleCounts[quality] &&
        overrides["enableBloom"] as? Bool == false &&
        Self.number(variant["renderScale"], equals: Self.snowfallRenderScales[quality]!) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.snowfallFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseBlueSkyDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2BlueSkyLayer? {
    guard
      let layer = Self.singleProgramLayer(
        document,
        role: "background",
        frameRateBinding: "staticContent",
        preferredFramesPerSecond: 1,
        transitionStrategy: "atomicParameters"
      ),
      (layer.node["resourceSlots"] as? [Any])?.isEmpty == true,
      (layer.node["signalBindings"] as? [Any])?.isEmpty == true,
      Self.validBlueSkyParameters(layer.node["parameters"]),
      Self.validPassiveShaderVariants(layer.node["qualityVariants"], framesPerSecond: 1)
    else { return nil }
    return SceneRenderV2BlueSkyLayer(
      id: layer.id,
      opacity: layer.opacity,
      renderScales: Self.passiveShaderRenderScales
    )
  }

  private static func parseMagicMoonDocument(
    _ document: [String: Any],
    loadImage: Bool
  ) -> SceneRenderV2MagicMoonLayer? {
    guard
      let layer = Self.singleProgramLayer(
        document,
        role: "overlay",
        frameRateBinding: "preferred",
        preferredFramesPerSecond: 1,
        transitionStrategy: "stateReplay"
      ),
      (layer.node["signalBindings"] as? [Any])?.isEmpty == true,
      Self.validMagicMoonParameters(layer.node["parameters"]),
      Self.validPassiveShaderVariants(layer.node["qualityVariants"], framesPerSecond: 1),
      let resources = layer.node["resourceSlots"] as? [[String: Any]],
      resources.count == 1,
      let texture = Self.decodeSingleImageResource(
        resources[0],
        expectedSlot: "primary",
        loadImage: loadImage
      )
    else { return nil }
    return SceneRenderV2MagicMoonLayer(
      id: layer.id,
      opacity: layer.opacity,
      texture: texture,
      renderScales: Self.passiveShaderRenderScales,
      framesPerSecondByQuality: Self.magicMoonFramesPerSecond
    )
  }

  private static func singleProgramLayer(
    _ document: [String: Any],
    role: String,
    frameRateBinding: String,
    preferredFramesPerSecond: Int,
    transitionStrategy: String,
    blendMode: String = "sourceOver"
  ) -> (id: String, opacity: CGFloat, node: [String: Any])? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layer["role"] as? String == role,
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == blendMode,
      layer["frameRateBinding"] as? String == frameRateBinding,
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue ==
        preferredFramesPerSecond,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.identityTransform(layer["transform"]),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.shaderProgram",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == transitionStrategy
    else { return nil }
    return (layerID, opacity, node)
  }

  private static func validBlueSkyParameters(_ value: Any?) -> Bool {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys) == Set(["programId", "seed", "parameters", "audioReactive"]),
      parameters["programId"] as? String == "blue_sky_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 0,
      parameters["audioReactive"] as? Bool == false,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "topColorArgb", "bottomColorArgb", "cloudsEnabled",
        "sourceFramesPerSecond",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      (recipe["topColorArgb"] as? NSNumber)?.int64Value == 0xff000000,
      (recipe["bottomColorArgb"] as? NSNumber)?.int64Value == 0xff311b92,
      recipe["cloudsEnabled"] as? Bool == false,
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 1
    else { return false }
    return true
  }

  private static func validMagicMoonParameters(_ value: Any?) -> Bool {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys) == Set(["programId", "seed", "parameters", "audioReactive"]),
      parameters["programId"] as? String == "magic_moon_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 0,
      parameters["audioReactive"] as? Bool == false,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "clockSource", "cycleMicros", "startX", "travelX",
        "centerY", "arcAmplitude", "normalizedRadius", "textureOpacity",
        "broadGlowRadiusScale", "broadGlowStops", "broadGlowColorsArgb",
        "rimAuraRadiusScale", "rimAuraStops", "rimAuraColorsArgb",
        "sourceFramesPerSecond",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      recipe["clockSource"] as? String == "unixEpoch",
      (recipe["cycleMicros"] as? NSNumber)?.int64Value == 5_400_000_000,
      Self.number(recipe["startX"], equals: 1.26),
      Self.number(recipe["travelX"], equals: 1.52),
      Self.number(recipe["centerY"], equals: 0.28),
      Self.number(recipe["arcAmplitude"], equals: 0.11),
      Self.number(recipe["normalizedRadius"], equals: 0.052),
      Self.number(recipe["textureOpacity"], equals: 0.5),
      Self.number(recipe["broadGlowRadiusScale"], equals: 3.8),
      Self.numberArray(recipe["broadGlowStops"], equals: [0, 0.28, 0.62, 1]),
      Self.integerArray(recipe["broadGlowColorsArgb"], equals: [
        0x107183ad, 0x075e7199, 0x0252648d, 0x0052648d,
      ]),
      Self.number(recipe["rimAuraRadiusScale"], equals: 1.65),
      Self.numberArray(recipe["rimAuraStops"], equals: [0, 0.5, 0.58, 0.74, 1]),
      Self.integerArray(recipe["rimAuraColorsArgb"], equals: [
        0x00d6e2ff, 0x00d6e2ff, 0x28c9d8f7, 0x0c9fb4de, 0x009fb4de,
      ]),
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 1
    else { return false }
    return true
  }

  private static func parseRadiantEmissionDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2RadiantEmissionLayer? {
    guard
      let layer = Self.singleProgramLayer(
        document,
        role: "overlay",
        frameRateBinding: "preferred",
        preferredFramesPerSecond: 30,
        transitionStrategy: "stateReplay",
        blendMode: "add"
      ),
      (layer.node["resourceSlots"] as? [Any])?.isEmpty == true,
      Self.validStrobeBindings(layer.node["signalBindings"], required: true),
      let recipe = Self.validRadiantEmissionParameters(layer.node["parameters"]),
      Self.validRadiantEmissionVariants(layer.node["qualityVariants"])
    else { return nil }
    return SceneRenderV2RadiantEmissionLayer(
      id: layer.id,
      opacity: layer.opacity,
      centerX: recipe.centerX,
      centerY: recipe.centerY,
      intensity: recipe.intensity,
      renderScales: Self.radiantEmissionRenderScales,
      framesPerSecondByQuality: Self.radiantEmissionFramesPerSecond,
      intensityScaleByQuality: Self.radiantEmissionIntensityScales
    )
  }

  private static func validRadiantEmissionParameters(
    _ value: Any?
  ) -> (centerX: Double, centerY: Double, intensity: Double)? {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys).isSubset(of: Set([
        "programId", "seed", "parameters", "audioReactive", "mode",
      ])),
      parameters["programId"] as? String == "radiant_emission_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 0,
      parameters["audioReactive"] as? Bool == true,
      parameters["mode"] == nil || parameters["mode"] is String,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "preset", "centerX", "centerY", "intensity",
        "pulseDurationMicros", "pulseCapacity", "flowAttackSeconds",
        "flowReleaseSeconds", "bassAttackSeconds", "bassReleaseSeconds",
        "sourceFramesPerSecond",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      let preset = recipe["preset"] as? String,
      let centerX = Self.finite(recipe["centerX"]),
      let centerY = Self.finite(recipe["centerY"]),
      let intensity = Self.finite(recipe["intensity"]),
      (preset == "standard" || preset == "spiralCore"),
      Self.number(centerX, equals: 0.5),
      Self.number(centerY, equals: preset == "spiralCore" ? 0.51 : 0.5),
      Self.number(intensity, equals: preset == "spiralCore" ? 1 : 0.88),
      (recipe["pulseDurationMicros"] as? NSNumber)?.intValue == 1_050_000,
      (recipe["pulseCapacity"] as? NSNumber)?.intValue == 2,
      Self.number(recipe["flowAttackSeconds"], equals: 0.1),
      Self.number(recipe["flowReleaseSeconds"], equals: 1.0 / 4.2),
      Self.number(recipe["bassAttackSeconds"], equals: 0.1),
      Self.number(recipe["bassReleaseSeconds"], equals: 1.0 / 4.2),
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 30
    else { return nil }
    let mode = (parameters["mode"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard ["", "default", "spiral core"].contains(mode),
      preset == (mode == "spiral core" ? "spiralCore" : "standard")
    else { return nil }
    return (Double(centerX), Double(centerY), Double(intensity))
  }

  private static func validRadiantEmissionVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any],
            Set(variant.keys) == Set([
              "level", "parameterOverrides", "renderScale", "framesPerSecond",
              "resourceOverrides",
            ]),
            let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["intensityScale"]) &&
        Self.number(
          overrides["intensityScale"],
          equals: Self.radiantEmissionIntensityScales[quality]!
        ) &&
        Self.number(
          variant["renderScale"],
          equals: Self.radiantEmissionRenderScales[quality]!
        ) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.radiantEmissionFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseRainbowWaterfallDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2RainbowWaterfallLayer? {
    guard
      Self.rainbowWaterfallKernel != nil,
      let layer = Self.singleProgramLayer(
        document,
        role: "background",
        frameRateBinding: "preferred",
        preferredFramesPerSecond: 30,
        transitionStrategy: "stateReplay",
        blendMode: "sourceOver"
      ),
      (layer.node["resourceSlots"] as? [Any])?.isEmpty == true,
      Self.validStrobeBindings(layer.node["signalBindings"], required: true),
      Self.validRainbowWaterfallParameters(layer.node["parameters"]),
      Self.validRainbowWaterfallVariants(layer.node["qualityVariants"])
    else { return nil }
    return SceneRenderV2RainbowWaterfallLayer(
      id: layer.id,
      opacity: layer.opacity,
      renderScales: Self.rainbowWaterfallRenderScales,
      framesPerSecondByQuality: Self.rainbowWaterfallFramesPerSecond
    )
  }

  private static func validRainbowWaterfallParameters(_ value: Any?) -> Bool {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys) == Set(["programId", "seed", "parameters", "audioReactive"]),
      parameters["programId"] as? String == "rainbow_waterfall_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 0,
      parameters["audioReactive"] as? Bool == true,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "baseCyclesPerSecond", "maximumCyclesPerSecond",
        "pulseDecaySeconds", "bassAttackSeconds", "bassReleaseSeconds",
        "bodyAttackSeconds", "bodyReleaseSeconds", "energyAttackSeconds",
        "energyReleaseSeconds", "flowAttackSeconds", "flowReleaseSeconds",
        "speedAttackSeconds", "speedReleaseSeconds", "sourceFramesPerSecond",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      Self.number(recipe["baseCyclesPerSecond"], equals: 0.125),
      Self.number(recipe["maximumCyclesPerSecond"], equals: 11.3),
      Self.number(recipe["pulseDecaySeconds"], equals: 0.22),
      Self.number(recipe["bassAttackSeconds"], equals: 0.06),
      Self.number(recipe["bassReleaseSeconds"], equals: 0.38),
      Self.number(recipe["bodyAttackSeconds"], equals: 0.12),
      Self.number(recipe["bodyReleaseSeconds"], equals: 0.70),
      Self.number(recipe["energyAttackSeconds"], equals: 0.18),
      Self.number(recipe["energyReleaseSeconds"], equals: 0.85),
      Self.number(recipe["flowAttackSeconds"], equals: 0.22),
      Self.number(recipe["flowReleaseSeconds"], equals: 1.0),
      Self.number(recipe["speedAttackSeconds"], equals: 0.09),
      Self.number(recipe["speedReleaseSeconds"], equals: 0.48),
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 30
    else { return false }
    return true
  }

  private static func validRainbowWaterfallVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any],
            Set(variant.keys) == Set([
              "level", "parameterOverrides", "renderScale", "framesPerSecond",
              "resourceOverrides",
            ])
      else { return false }
      return variant["level"] as? String == quality &&
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true &&
        Self.number(
          variant["renderScale"],
          equals: Self.rainbowWaterfallRenderScales[quality]!
        ) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.rainbowWaterfallFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseNeonPulseDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2NeonPulseLayer? {
    guard
      let layer = Self.singleProgramLayer(
        document,
        role: "background",
        frameRateBinding: "preferred",
        preferredFramesPerSecond: 60,
        transitionStrategy: "stateReplay",
        blendMode: "sourceOver"
      ),
      (layer.node["resourceSlots"] as? [Any])?.isEmpty == true,
      Self.validStrobeBindings(layer.node["signalBindings"], required: true),
      Self.validNeonPulseParameters(layer.node["parameters"]),
      let parameters = layer.node["parameters"] as? [String: Any],
      let controls = SceneRenderV2NeonPulseControls.parse(parameters),
      Self.validNeonPulseVariants(layer.node["qualityVariants"])
    else { return nil }
    return SceneRenderV2NeonPulseLayer(
      id: layer.id,
      opacity: layer.opacity,
      renderScales: Self.neonPulseRenderScales,
      framesPerSecondByQuality: Self.neonPulseFramesPerSecond,
      maximumParticlesByQuality: Self.neonPulseMaximumParticles,
      controls: controls
    )
  }

  private static func validNeonPulseParameters(_ value: Any?) -> Bool {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys).isSubset(of: Set(["programId", "seed", "parameters", "audioReactive", "mode", "options"])),
      parameters["programId"] as? String == "neon_pulse_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 0,
      parameters["audioReactive"] as? Bool == true,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "animationOneWayMicros", "particleSize",
        "minimumParticleCount", "maximumParticleCount", "impactRadiusScale",
        "backgroundStartArgb", "backgroundPaletteArgb", "particlePaletteArgb",
        "sourceFramesPerSecond", "randomAlgorithm",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      (recipe["animationOneWayMicros"] as? NSNumber)?.intValue == 10_000_000,
      Self.number(recipe["particleSize"], equals: 1),
      (recipe["minimumParticleCount"] as? NSNumber)?.intValue == 50,
      (recipe["maximumParticleCount"] as? NSNumber)?.intValue == 200,
      Self.number(recipe["impactRadiusScale"], equals: 0.1),
      (recipe["backgroundStartArgb"] as? NSNumber)?.int64Value == 0xb3ffffff,
      Self.integerArray(recipe["backgroundPaletteArgb"], equals: [
        0xfff44336, 0xffffeb3b, 0xff00bcd4, 0xffffc107, 0xff4caf50,
        0xff2196f3, 0xffff9800, 0xff9c27b0, 0xffe91e63, 0xffcddc39,
        0xff3f51b5,
      ]),
      Self.integerArray(recipe["particlePaletteArgb"], equals: [
        0xfff44336, 0xffe91e63, 0xff9c27b0, 0xff673ab7, 0xff3f51b5,
        0xff2196f3, 0xff03a9f4, 0xff00bcd4, 0xff009688, 0xff4caf50,
        0xff8bc34a, 0xffcddc39, 0xffffeb3b, 0xffffc107, 0xffff9800,
        0xffff5722, 0xff795548, 0xff607d8b,
      ]),
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 60,
      recipe["randomAlgorithm"] as? String == "frame_hash_lcg32_v1"
    else { return false }
    return true
  }

  private static func validNeonPulseVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any],
            Set(variant.keys) == Set([
              "level", "parameterOverrides", "renderScale", "framesPerSecond",
              "resourceOverrides",
            ]),
            let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["maximumParticleCount"]) &&
        (overrides["maximumParticleCount"] as? NSNumber)?.intValue ==
          Self.neonPulseMaximumParticles[quality] &&
        Self.number(
          variant["renderScale"],
          equals: Self.neonPulseRenderScales[quality]!
        ) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.neonPulseFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseEmbeddedScreenDocument(
    _ document: [String: Any],
    loadImage: Bool
  ) -> SceneRenderV2EmbeddedScreenLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layer["role"] as? String == "overlay",
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 30,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      let transform = Self.parseTransform(layer["transform"]),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.embeddedScreen",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      Self.validStrobeBindings(node["signalBindings"], required: true),
      let parsed = Self.parseEmbeddedScreenParameters(node["parameters"]),
      Self.validEmbeddedScreenVariants(node["qualityVariants"]),
      let resources = node["resourceSlots"] as? [[String: Any]],
      resources.count == 1,
      let resource = resources.first,
      let source = Self.resolveEmbeddedScreenImage(resource, loadImage: loadImage)
    else { return nil }
    return SceneRenderV2EmbeddedScreenLayer(
      id: layerID,
      source: source,
      opacity: opacity,
      width: transform.width,
      height: transform.height,
      offsetX: transform.offsetX,
      offsetY: transform.offsetY,
      scale: transform.scale,
      rotation: transform.rotation,
      flipped: transform.flipped,
      renderScales: Self.embeddedScreenRenderScales,
      framesPerSecondByQuality: Self.embeddedScreenFramesPerSecond,
      ringCountsByQuality: Self.embeddedScreenRingCounts,
      rayCountsByQuality: Self.embeddedScreenRayCounts,
      spectrumSamplesByQuality: Self.embeddedScreenSpectrumSamples,
      topLeft: parsed.surface[0],
      topRight: parsed.surface[1],
      bottomRight: parsed.surface[2],
      bottomLeft: parsed.surface[3],
      mode: parsed.mode,
      backgroundARGB: parsed.backgroundARGB,
      primaryARGB: parsed.primaryARGB,
      accentARGB: parsed.accentARGB,
      idleOpacity: parsed.idleOpacity,
      glow: parsed.glow,
      lineWidth: parsed.lineWidth,
      flowGain: parsed.flowGain,
      bassGain: parsed.bassGain,
      bodyGain: parsed.bodyGain,
      sparkGain: parsed.sparkGain,
      attackSeconds: parsed.attackSeconds,
      releaseSeconds: parsed.releaseSeconds
    )
  }

  private struct EmbeddedScreenParameters {
    let surface: [SceneRenderV2EmbeddedScreenPoint]
    let mode: String
    let backgroundARGB: UInt32
    let primaryARGB: UInt32
    let accentARGB: UInt32
    let idleOpacity: Double
    let glow: Double
    let lineWidth: Double
    let flowGain: Double
    let bassGain: Double
    let bodyGain: Double
    let sparkGain: Double
    let attackSeconds: Double
    let releaseSeconds: Double
  }

  private static func parseEmbeddedScreenParameters(
    _ value: Any?
  ) -> EmbeddedScreenParameters? {
    guard
      let outer = value as? [String: Any],
      Set(outer.keys) == Set([
        "programId", "seed", "parameters", "ringCount", "rayCount",
        "spectrumSamples", "audioReactive", "effect",
      ]),
      outer["programId"] as? String == "embedded_screen_visualizer_v1",
      (outer["seed"] as? NSNumber)?.intValue == 0,
      (outer["ringCount"] as? NSNumber)?.intValue == 4,
      (outer["rayCount"] as? NSNumber)?.intValue == 10,
      (outer["spectrumSamples"] as? NSNumber)?.intValue == 17,
      outer["audioReactive"] as? Bool == true,
      let recipe = outer["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "surface", "style", "response", "performance",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      let surfaceValue = recipe["surface"] as? [String: Any],
      Set(surfaceValue.keys) == Set([
        "topLeft", "topRight", "bottomRight", "bottomLeft",
      ]),
      let topLeft = Self.embeddedScreenPoint(surfaceValue["topLeft"]),
      let topRight = Self.embeddedScreenPoint(surfaceValue["topRight"]),
      let bottomRight = Self.embeddedScreenPoint(surfaceValue["bottomRight"]),
      let bottomLeft = Self.embeddedScreenPoint(surfaceValue["bottomLeft"]),
      Self.embeddedScreenConvex([topLeft, topRight, bottomRight, bottomLeft]),
      let style = recipe["style"] as? [String: Any],
      Set(style.keys) == Set([
        "mode", "backgroundArgb", "primaryArgb", "accentArgb", "idleOpacity",
        "glow", "lineWidth",
      ]),
      let mode = style["mode"] as? String,
      ["centeredSpectralWave", "prismaticSpectrumField"].contains(mode),
      let background = Self.embeddedScreenARGB(style["backgroundArgb"]),
      let primary = Self.embeddedScreenARGB(style["primaryArgb"]),
      let accent = Self.embeddedScreenARGB(style["accentArgb"]),
      let idleOpacity = Self.embeddedScreenDouble(style["idleOpacity"], 0.2, 1),
      let glow = Self.embeddedScreenDouble(style["glow"], 0, 1),
      let lineWidth = Self.embeddedScreenDouble(style["lineWidth"], 0.004, 0.05),
      let response = recipe["response"] as? [String: Any],
      Set(response.keys) == Set([
        "flowGain", "bassGain", "bodyGain", "sparkGain", "attackMicros",
        "releaseMicros",
      ]),
      let flowGain = Self.embeddedScreenDouble(response["flowGain"], 0, 1.5),
      let bassGain = Self.embeddedScreenDouble(response["bassGain"], 0, 1.5),
      let bodyGain = Self.embeddedScreenDouble(response["bodyGain"], 0, 1.5),
      let sparkGain = Self.embeddedScreenDouble(response["sparkGain"], 0, 1.5),
      let attackMicros = (response["attackMicros"] as? NSNumber)?.int64Value,
      (16_000...1_000_000).contains(attackMicros),
      let releaseMicros = (response["releaseMicros"] as? NSNumber)?.int64Value,
      (50_000...5_000_000).contains(releaseMicros),
      let performance = recipe["performance"] as? [String: Any],
      Set(performance.keys) == Set([
        "preferredFramesPerSecond", "idleFramesPerSecond", "costUnits",
      ]),
      (performance["preferredFramesPerSecond"] as? NSNumber)?.intValue == 30,
      let idleFrames = (performance["idleFramesPerSecond"] as? NSNumber)?.intValue,
      (1...15).contains(idleFrames),
      Self.embeddedScreenDouble(performance["costUnits"], 0.05, 0.4) != nil
    else { return nil }
    return EmbeddedScreenParameters(
      surface: [topLeft, topRight, bottomRight, bottomLeft],
      mode: mode,
      backgroundARGB: background,
      primaryARGB: primary,
      accentARGB: accent,
      idleOpacity: idleOpacity,
      glow: glow,
      lineWidth: lineWidth,
      flowGain: flowGain,
      bassGain: bassGain,
      bodyGain: bodyGain,
      sparkGain: sparkGain,
      attackSeconds: Double(attackMicros) / 1_000_000,
      releaseSeconds: Double(releaseMicros) / 1_000_000
    )
  }

  private static func validEmbeddedScreenVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard
        let variant = variants[quality] as? [String: Any],
        Set(variant.keys) == Set([
          "level", "parameterOverrides", "renderScale", "framesPerSecond",
          "resourceOverrides",
        ]),
        let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["ringCount", "rayCount", "spectrumSamples"]) &&
        (overrides["ringCount"] as? NSNumber)?.intValue ==
          Self.embeddedScreenRingCounts[quality] &&
        (overrides["rayCount"] as? NSNumber)?.intValue ==
          Self.embeddedScreenRayCounts[quality] &&
        (overrides["spectrumSamples"] as? NSNumber)?.intValue ==
          Self.embeddedScreenSpectrumSamples[quality] &&
        Self.number(
          variant["renderScale"],
          equals: Self.embeddedScreenRenderScales[quality]!
        ) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.embeddedScreenFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseWaveformDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2WaveformLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layer["role"] as? String == "overlay",
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 24,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.parseTransform(layer["transform"]) != nil,
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.waveform",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      (node["resourceSlots"] as? [[String: Any]])?.isEmpty == true,
      Self.validStrobeBindings(node["signalBindings"], required: true),
      let parsed = Self.parseWaveformParameters(node["parameters"]),
      Self.validWaveformVariants(node["qualityVariants"])
    else { return nil }
    return SceneRenderV2WaveformLayer(
      id: layerID,
      opacity: Double(opacity),
      renderScales: Self.waveformRenderScales,
      framesPerSecondByQuality: Self.waveformFramesPerSecond,
      sampleCountsByQuality: Self.waveformSampleCounts,
      spectralNodeCountsByQuality: Self.waveformSpectralNodeCounts,
      glowPassesByQuality: Self.waveformGlowPasses,
      idleVisibility: parsed.idleVisibility,
      zeroThreshold: parsed.zeroThreshold,
      maximumDisplacementHeightFraction: parsed.maximumHeightFraction,
      maximumDisplacementWidthFraction: parsed.maximumWidthFraction,
      outerARGB: parsed.outerARGB,
      peakARGB: parsed.peakARGB,
      hotCoreARGB: parsed.hotCoreARGB,
      innerARGB: parsed.innerARGB,
      coreARGB: parsed.coreARGB,
      responseSeconds: parsed.responseSeconds
    )
  }

  private struct WaveformParameters {
    let idleVisibility: Double
    let zeroThreshold: Double
    let maximumHeightFraction: Double
    let maximumWidthFraction: Double
    let outerARGB: UInt32
    let peakARGB: UInt32
    let hotCoreARGB: UInt32
    let innerARGB: UInt32
    let coreARGB: UInt32
    let responseSeconds: [Double]
  }

  private static func parseWaveformParameters(_ value: Any?) -> WaveformParameters? {
    guard
      let outer = value as? [String: Any],
      Set(outer.keys) == Set([
        "programId", "seed", "parameters", "sampleCount", "spectralNodeCount",
        "glowPasses", "audioReactive",
      ]),
      outer["programId"] as? String == "music_waveform_v1",
      (outer["seed"] as? NSNumber)?.intValue == 0,
      (outer["sampleCount"] as? NSNumber)?.intValue == 127,
      (outer["spectralNodeCount"] as? NSNumber)?.intValue == 15,
      (outer["glowPasses"] as? NSNumber)?.intValue == 5,
      outer["audioReactive"] as? Bool == true,
      let recipe = outer["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "sourceFramesPerSecond", "sampleCount", "spectralNodeCount",
        "idleVisibility", "zeroThreshold", "maximumDisplacementHeightFraction",
        "maximumDisplacementWidthFraction", "style", "response",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 24,
      (recipe["sampleCount"] as? NSNumber)?.intValue == 127,
      (recipe["spectralNodeCount"] as? NSNumber)?.intValue == 15,
      let idleVisibility = Self.waveformDouble(recipe["idleVisibility"], 0, 1),
      let zeroThreshold = Self.waveformDouble(recipe["zeroThreshold"], 0, 0.01),
      let maximumHeight = Self.waveformDouble(
        recipe["maximumDisplacementHeightFraction"], 0, 0.5
      ),
      let maximumWidth = Self.waveformDouble(
        recipe["maximumDisplacementWidthFraction"], 0, 0.5
      ),
      let style = recipe["style"] as? [String: Any],
      Set(style.keys) == Set([
        "outerArgb", "peakArgb", "hotCoreArgb", "innerArgb", "coreArgb",
        "outerBlur", "peakBlur", "hotCoreBlur", "haloBlur",
      ]),
      let outerARGB = Self.waveformARGB(style["outerArgb"]),
      let peakARGB = Self.waveformARGB(style["peakArgb"]),
      let hotCoreARGB = Self.waveformARGB(style["hotCoreArgb"]),
      let innerARGB = Self.waveformARGB(style["innerArgb"]),
      let coreARGB = Self.waveformARGB(style["coreArgb"]),
      Self.number(style["outerBlur"], equals: 24),
      Self.number(style["peakBlur"], equals: 13),
      Self.number(style["hotCoreBlur"], equals: 3),
      Self.number(style["haloBlur"], equals: 8),
      let response = recipe["response"] as? [String: Any]
    else { return nil }
    let responseKeys = [
      "bassAttackSeconds", "bassReleaseSeconds", "bodyAttackSeconds",
      "bodyReleaseSeconds", "sparkAttackSeconds", "sparkReleaseSeconds",
      "flowAttackSeconds", "flowReleaseSeconds", "levelAttackSeconds",
      "levelReleaseSeconds",
    ]
    guard Set(response.keys) == Set(responseKeys) else { return nil }
    let responseSeconds = responseKeys.compactMap {
      Self.waveformDouble(response[$0], 0.001, 2)
    }
    guard responseSeconds.count == responseKeys.count else { return nil }
    return WaveformParameters(
      idleVisibility: idleVisibility,
      zeroThreshold: zeroThreshold,
      maximumHeightFraction: maximumHeight,
      maximumWidthFraction: maximumWidth,
      outerARGB: outerARGB,
      peakARGB: peakARGB,
      hotCoreARGB: hotCoreARGB,
      innerARGB: innerARGB,
      coreARGB: coreARGB,
      responseSeconds: responseSeconds
    )
  }

  private static func validWaveformVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard
        let variant = variants[quality] as? [String: Any],
        Set(variant.keys) == Set([
          "level", "parameterOverrides", "renderScale", "framesPerSecond",
          "resourceOverrides",
        ]),
        let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["sampleCount", "spectralNodeCount", "glowPasses"]) &&
        (overrides["sampleCount"] as? NSNumber)?.intValue ==
          Self.waveformSampleCounts[quality] &&
        (overrides["spectralNodeCount"] as? NSNumber)?.intValue ==
          Self.waveformSpectralNodeCounts[quality] &&
        (overrides["glowPasses"] as? NSNumber)?.intValue ==
          Self.waveformGlowPasses[quality] &&
        Self.number(variant["renderScale"], equals: Self.waveformRenderScales[quality]!) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.waveformFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseInstalledProgramDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2InstalledProgramLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate",
        "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      let role = layer["role"] as? String,
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      layer["frameRateBinding"] as? String == "preferred",
      let preferredFPS = (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue,
      (1...60).contains(preferredFPS),
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.identityTransform(layer["transform"]),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "program.installed",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      Self.validStrobeBindings(node["signalBindings"], required: true),
      let parameters = node["parameters"] as? [String: Any],
      Set(parameters.keys).isSubset(of: Set([
        "programId", "seed", "palette", "parameters", "audioReactive", "runtime",
      ])),
      parameters["audioReactive"] as? Bool == true,
      let programID = parameters["programId"] as? String,
      let program = SceneRenderV2InstalledProgramKind(rawValue: programID),
      let variants = Self.parseImageVariants(
        node["qualityVariants"],
        preferredFramesPerSecond: preferredFPS,
        reactive: true
      )
    else { return nil }

    let expectedRole: String
    let expectedFPS: Int
    switch program {
    case .blindingColors:
      expectedRole = "background"; expectedFPS = 60
    case .liquidLava:
      expectedRole = "background"; expectedFPS = 30
    case .enchantedFireflies:
      expectedRole = "overlay"; expectedFPS = 30
    case .infernoEmbers, .wildflowerPollen:
      expectedRole = "overlay"; expectedFPS = 24
    case .statefulStorm:
      expectedRole = "overlay"; expectedFPS = 30
    }
    guard role == expectedRole, preferredFPS == expectedFPS else { return nil }

    let recipe = parameters["parameters"] as? [String: Any] ?? [:]
    let authoredSeedNumber = (parameters["seed"] ?? recipe["seed"]) as? NSNumber
    let authoredSeed = authoredSeedNumber?.int64Value ?? 1
    guard authoredSeed >= 0, authoredSeed <= Int64(UInt32.max) else { return nil }
    let paletteNumbers = parameters["palette"] as? [NSNumber] ?? []
    guard paletteNumbers.allSatisfy({ $0.int64Value >= 0 &&
      $0.int64Value <= Int64(UInt32.max) }) else { return nil }
    let palette = paletteNumbers.map { Self.color(argb: UInt32($0.int64Value)) }

    let programIsValid: Bool = switch program {
    case .blindingColors:
      recipe.isEmpty && palette.isEmpty && parameters["seed"] != nil
    case .liquidLava:
      recipe.isEmpty && palette.count == 3
    case .enchantedFireflies:
      palette.count == 3 && SceneSurfaceFirefliesRecipeV1(recipe) != nil
    case .infernoEmbers:
      palette.count == 3 && SceneSurfaceInfernoEmbersRecipeV1(recipe) != nil
    case .wildflowerPollen:
      palette.count == 3 && SceneSurfaceWildflowerPollenRecipeV1(recipe) != nil
    case .statefulStorm:
      palette.count == 3 && SceneSurfaceStatefulStormRecipeV1(recipe) != nil
    }
    guard programIsValid else { return nil }
    guard let configurationSignature =
      SceneRenderV2ShadowCompiler.semanticPlanHash(document: document)
    else { return nil }
    return SceneRenderV2InstalledProgramLayer(
      id: layerID,
      configurationSignature: configurationSignature,
      opacity: opacity,
      program: program,
      authoredSeed: UInt64(authoredSeed),
      palette: palette,
      recipe: recipe,
      renderScales: variants.scales,
      framesPerSecondByQuality: variants.framesPerSecond
    )
  }

  private static func color(argb: UInt32) -> CIColor {
    CIColor(
      red: CGFloat((argb >> 16) & 0xff) / 255,
      green: CGFloat((argb >> 8) & 0xff) / 255,
      blue: CGFloat(argb & 0xff) / 255,
      alpha: CGFloat((argb >> 24) & 0xff) / 255
    )
  }

  private static func waveformARGB(_ value: Any?) -> UInt32? {
    guard let raw = (value as? NSNumber)?.int64Value,
          raw >= 0, raw <= Int64(UInt32.max) else { return nil }
    return UInt32(raw)
  }

  private static func waveformDouble(
    _ value: Any?,
    _ minimum: Double,
    _ maximum: Double
  ) -> Double? {
    guard let raw = (value as? NSNumber)?.doubleValue,
          raw.isFinite, raw >= minimum, raw <= maximum else { return nil }
    return raw
  }

  private static func resolveEmbeddedScreenImage(
    _ resource: [String: Any],
    loadImage: Bool
  ) -> CIImage? {
    guard
      resource["slot"] as? String == "primary",
      resource["kind"] as? String == "image",
      let resourceID = resource["resourceId"] as? String,
      validToken(resourceID),
      resource["uri"] == nil
    else { return nil }
    let asset = resource["asset"] as? String
    let path = resource["path"] as? String
    guard (asset == nil) != (path == nil) else { return nil }
    let package = resource["assetPackage"] as? String
    guard asset != nil || package == nil else { return nil }
    var keys = Set(["slot", "resourceId", "kind"])
    if asset != nil { keys.insert("asset") }
    if path != nil { keys.insert("path") }
    if package != nil { keys.insert("assetPackage") }
    if resource["sha256"] != nil { keys.insert("sha256") }
    guard Set(resource.keys) == keys else { return nil }
    if let digest = resource["sha256"] as? String,
       digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
      return nil
    }
    guard loadImage else { return CIImage.empty() }
    let url: URL
    if let asset {
      guard !asset.isEmpty else { return nil }
      let key = package.map {
        FlutterDartProject.lookupKey(forAsset: asset, fromPackage: $0)
      } ?? FlutterDartProject.lookupKey(forAsset: asset)
      guard let resolved = Bundle.main.path(forResource: key, ofType: nil) else {
        return nil
      }
      url = URL(fileURLWithPath: resolved)
    } else {
      guard let path, !path.isEmpty,
            !path.hasPrefix("http:"), !path.hasPrefix("https:") else { return nil }
      url = URL(fileURLWithPath: path)
    }
    if let digest = resource["sha256"] as? String, Self.sha256File(url) != digest {
      return nil
    }
    guard
      let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(imageSource) == 1,
      let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      decoded.width > 0, decoded.height > 0,
      decoded.width <= 8192, decoded.height <= 8192,
      decoded.width * decoded.height <= 33_554_432
    else { return nil }
    return CIImage(cgImage: decoded)
  }

  private static func embeddedScreenPoint(
    _ value: Any?
  ) -> SceneRenderV2EmbeddedScreenPoint? {
    guard
      let values = value as? [NSNumber],
      values.count == 2,
      values[0].doubleValue.isFinite,
      values[1].doubleValue.isFinite,
      (-0.25...1.25).contains(values[0].doubleValue),
      (-0.25...1.25).contains(values[1].doubleValue)
    else { return nil }
    return SceneRenderV2EmbeddedScreenPoint(
      x: values[0].doubleValue,
      y: values[1].doubleValue
    )
  }

  private static func embeddedScreenConvex(
    _ points: [SceneRenderV2EmbeddedScreenPoint]
  ) -> Bool {
    guard points.count == 4 else { return false }
    var sign = 0
    for index in points.indices {
      let a = points[index]
      let b = points[(index + 1) % points.count]
      let c = points[(index + 2) % points.count]
      let cross = (b.x - a.x) * (c.y - b.y) -
        (b.y - a.y) * (c.x - b.x)
      guard abs(cross) >= 0.000_001 else { return false }
      let next = cross > 0 ? 1 : -1
      if sign != 0, sign != next { return false }
      sign = next
    }
    return true
  }

  private static func embeddedScreenARGB(_ value: Any?) -> UInt32? {
    guard let raw = (value as? NSNumber)?.int64Value,
          raw >= 0, raw <= Int64(UInt32.max) else { return nil }
    return UInt32(raw)
  }

  private static func embeddedScreenDouble(
    _ value: Any?,
    _ minimum: Double,
    _ maximum: Double
  ) -> Double? {
    guard let raw = (value as? NSNumber)?.doubleValue,
          raw.isFinite, raw >= minimum, raw <= maximum else { return nil }
    return raw
  }

  private static func validPassiveShaderVariants(
    _ value: Any?,
    framesPerSecond: Int
  ) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any] else { return false }
      return Set(variant.keys) == Set([
        "level", "parameterOverrides", "renderScale", "framesPerSecond",
        "resourceOverrides",
      ]) && variant["level"] as? String == quality &&
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true &&
        Self.number(
          variant["renderScale"],
          equals: Self.passiveShaderRenderScales[quality]!
        ) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue == framesPerSecond &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func decodeSingleImageResource(
    _ resource: [String: Any],
    expectedSlot: String,
    loadImage: Bool
  ) -> CIImage? {
    var allowed = Set(["slot", "resourceId", "kind", "asset"])
    if resource["assetPackage"] != nil { allowed.insert("assetPackage") }
    if resource["sha256"] != nil { allowed.insert("sha256") }
    guard
      Set(resource.keys) == allowed,
      resource["slot"] as? String == expectedSlot,
      resource["kind"] as? String == "image",
      let resourceID = resource["resourceId"] as? String,
      validToken(resourceID),
      let asset = resource["asset"] as? String,
      !asset.isEmpty,
      resource["sha256"] == nil ||
        ((resource["sha256"] as? String)?.range(
          of: "^[0-9a-f]{64}$", options: .regularExpression
        ) != nil)
    else { return nil }
    guard loadImage else { return CIImage.empty() }
    let package = resource["assetPackage"] as? String
    let key = package.map {
      FlutterDartProject.lookupKey(forAsset: asset, fromPackage: $0)
    } ?? FlutterDartProject.lookupKey(forAsset: asset)
    guard
      let path = Bundle.main.path(forResource: key, ofType: nil),
      let imageSource = CGImageSourceCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, nil
      ),
      CGImageSourceGetCount(imageSource) == 1,
      let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      decoded.width > 0, decoded.height > 0,
      decoded.width <= 8192, decoded.height <= 8192,
      decoded.width * decoded.height <= 33_554_432
    else { return nil }
    return CIImage(cgImage: decoded)
  }

  private static func numberArray(_ value: Any?, equals expected: [Double]) -> Bool {
    guard let values = value as? [NSNumber], values.count == expected.count else {
      return false
    }
    return zip(values, expected).allSatisfy { number, expected in
      number.doubleValue.isFinite && number.doubleValue == expected
    }
  }

  private static func integerArray(_ value: Any?, equals expected: [Int64]) -> Bool {
    guard let values = value as? [NSNumber], values.count == expected.count else {
      return false
    }
    return zip(values, expected).allSatisfy { $0.int64Value == $1 }
  }

  private static func parseMagicStarsDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2MagicStarsLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layer["role"] as? String == "overlay",
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 60,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.identityTransform(layer["transform"]),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.shaderProgram",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      Self.validStrobeBindings(node["signalBindings"], required: true),
      Self.validMagicStarsParameters(node["parameters"]),
      let parameters = node["parameters"] as? [String: Any],
      let controls = SceneRenderV2MagicStarsControls.parse(parameters),
      Self.validMagicStarsVariants(node["qualityVariants"])
    else { return nil }
    return SceneRenderV2MagicStarsLayer(
      id: layerID,
      opacity: opacity,
      renderScales: Self.magicStarsRenderScales,
      framesPerSecondByQuality: Self.magicStarsFramesPerSecond,
      intensityScaleByQuality: Self.magicStarsIntensityScales,
      controls: controls
    )
  }

  private static func validMagicStarsParameters(_ value: Any?) -> Bool {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys).isSubset(of: Set(["programId", "seed", "parameters", "audioReactive", "options"])),
      parameters["programId"] as? String == "magic_stars_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 0,
      parameters["audioReactive"] as? Bool == true,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "dynamicCount", "staticCount", "bias", "flashingFraction",
        "shootingStarProbability", "shootingStarDurationMicros",
        "shootingStarAttemptMicros", "starSize", "reactiveGlowRadiusScale",
        "colorArgb", "sourceFramesPerSecond", "randomAlgorithm",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      (recipe["dynamicCount"] as? NSNumber)?.intValue == 170,
      (recipe["staticCount"] as? NSNumber)?.intValue == 10,
      Self.number(recipe["bias"], equals: 0.5),
      Self.number(recipe["flashingFraction"], equals: 0.5),
      Self.number(recipe["shootingStarProbability"], equals: 0.05),
      (recipe["shootingStarDurationMicros"] as? NSNumber)?.int64Value == 3_000_000,
      (recipe["shootingStarAttemptMicros"] as? NSNumber)?.int64Value == 1_000_000,
      Self.number(recipe["starSize"], equals: 1),
      Self.number(recipe["reactiveGlowRadiusScale"], equals: 1.62),
      (recipe["colorArgb"] as? NSNumber)?.int64Value == 0xccffffff,
      (recipe["sourceFramesPerSecond"] as? NSNumber)?.intValue == 60,
      recipe["randomAlgorithm"] as? String == "lcg32_v1"
    else { return false }
    return true
  }

  private static func validMagicStarsVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any],
            Set(variant.keys) == Set([
              "level", "parameterOverrides", "renderScale", "framesPerSecond",
              "resourceOverrides",
            ]),
            let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["intensityScale"]) &&
        Self.number(
          overrides["intensityScale"],
          equals: Self.magicStarsIntensityScales[quality]!
        ) &&
        Self.number(variant["renderScale"], equals: Self.magicStarsRenderScales[quality]!) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.magicStarsFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parsePaintedStarlightDocument(
    _ document: [String: Any]
  ) -> SceneRenderV2PaintedStarlightLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layer["role"] as? String == "overlay",
      let opacity = Self.finite(layer["opacity"]), opacity >= 0, opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 30,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      Self.identityTransform(layer["transform"]),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots", "signalBindings",
        "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.shaderProgram",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      Self.validStrobeBindings(node["signalBindings"], required: true),
      Self.validPaintedStarlightParameters(node["parameters"]),
      Self.validPaintedStarlightVariants(node["qualityVariants"])
    else { return nil }
    return SceneRenderV2PaintedStarlightLayer(
      id: layerID,
      opacity: opacity,
      renderScales: Self.paintedStarlightRenderScales,
      framesPerSecondByQuality: Self.paintedStarlightFramesPerSecond,
      intensityScaleByQuality: Self.paintedStarlightIntensityScales
    )
  }

  private static func validPaintedStarlightParameters(_ value: Any?) -> Bool {
    guard
      let parameters = value as? [String: Any],
      Set(parameters.keys).subtracting(["mode"]) ==
        Set(["programId", "seed", "parameters", "audioReactive"]),
      parameters["mode"] == nil || parameters["mode"] as? String == "" ||
        parameters["mode"] as? String == "default",
      parameters["programId"] as? String == "painted_starlight_pulse_v1",
      (parameters["seed"] as? NSNumber)?.intValue == 0,
      parameters["audioReactive"] as? Bool == true,
      let recipe = parameters["parameters"] as? [String: Any],
      Set(recipe.keys) == Set([
        "schemaVersion", "sourceWidth", "sourceHeight", "framesPerSecond",
        "intensityBandCount", "moon", "stars", "flowAttackSeconds",
        "flowReleaseSeconds", "sparkAttackSeconds", "sparkReleaseSeconds",
      ]),
      (recipe["schemaVersion"] as? NSNumber)?.intValue == 1,
      Self.number(recipe["sourceWidth"], equals: 936),
      Self.number(recipe["sourceHeight"], equals: 1664),
      (recipe["framesPerSecond"] as? NSNumber)?.intValue == 30,
      (recipe["intensityBandCount"] as? NSNumber)?.intValue == 16,
      Self.validPaintedStarlightNode(recipe["moon"], x: 0.807, y: 0.144, radius: 0.245),
      let stars = recipe["stars"] as? [[String: Any]], stars.count == 5,
      Self.validPaintedStarlightNode(stars[0], x: 0.139, y: 0.075, radius: 0.086),
      Self.validPaintedStarlightNode(stars[1], x: 0.635, y: 0.343, radius: 0.073),
      Self.validPaintedStarlightNode(stars[2], x: 0.895, y: 0.497, radius: 0.088),
      Self.validPaintedStarlightNode(stars[3], x: 0.171, y: 0.798, radius: 0.076),
      Self.validPaintedStarlightNode(stars[4], x: 0.548, y: 0.879, radius: 0.067),
      Self.number(recipe["flowAttackSeconds"], equals: 0.38),
      Self.number(recipe["flowReleaseSeconds"], equals: 1.35),
      Self.number(recipe["sparkAttackSeconds"], equals: 0.06),
      Self.number(recipe["sparkReleaseSeconds"], equals: 0.42)
    else { return false }
    return true
  }

  private static func validPaintedStarlightNode(
    _ value: Any?,
    x: Double,
    y: Double,
    radius: Double
  ) -> Bool {
    guard let node = value as? [String: Any],
          Set(node.keys) == Set(["centerX", "centerY", "radius"])
    else { return false }
    return Self.number(node["centerX"], equals: x) &&
      Self.number(node["centerY"], equals: y) &&
      Self.number(node["radius"], equals: radius)
  }

  private static func validPaintedStarlightVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any],
            Set(variant.keys) == Set([
              "level", "parameterOverrides", "renderScale", "framesPerSecond",
              "resourceOverrides",
            ]),
            let overrides = variant["parameterOverrides"] as? [String: Any]
      else { return false }
      return variant["level"] as? String == quality &&
        Set(overrides.keys) == Set(["intensityScale"]) &&
        Self.number(
          overrides["intensityScale"],
          equals: Self.paintedStarlightIntensityScales[quality]!
        ) &&
        Self.number(
          variant["renderScale"],
          equals: Self.paintedStarlightRenderScales[quality]!
        ) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.paintedStarlightFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseFilterGrade(_ value: Any?) -> FilterGrade? {
    guard
      let node = value as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots",
        "signalBindings", "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "post.filterGrade",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      (node["signalBindings"] as? [Any])?.isEmpty == true,
      node["transitionStrategy"] as? String == "atomicParameters",
      Self.validFilterVariants(node["qualityVariants"]),
      let parameters = node["parameters"] as? [String: Any],
      Set(parameters.keys) == Set(["filterId", "intensity", "parameters"]),
      let filterID = parameters["filterId"] as? String,
      validToken(filterID),
      let intensity = Self.bounded(parameters["intensity"], minimum: 0, maximum: 1),
      let rawValues = parameters["parameters"] as? [String: Any]
    else { return nil }
    return parseFilterValues(rawValues, filterID: filterID, intensity: intensity)
  }

  private static func parseFilterValues(
    _ rawValues: [String: Any], filterID: String, intensity: CGFloat
  ) -> FilterGrade? {
    let values: [String: Any]
    if Set(rawValues.keys) == Set(["engine", "values"]) {
      guard rawValues["engine"] as? String == "grade_v2",
            let explicitValues = rawValues["values"] as? [String: Any]
      else { return nil }
      values = explicitValues
    } else {
      // The V1 shadow adapter still emits the raw grade values. Manifest V48
      // uses the explicit grade_v2 envelope above.
      values = rawValues
    }
    guard
      Set(values.keys) == Set([
        "exposure", "contrast", "saturation", "vibrance", "temperature",
        "tint", "blackLift", "highlightRolloff", "shadowDepth",
        "midtoneBalance", "colorDensity", "cyanPresence", "magentaPresence",
        "goldPresence", "shadows", "midtones", "highlights", "vignette",
        "vignetteSoftness",
      ]),
      let exposure = Self.bounded(values["exposure"], minimum: -1, maximum: 1),
      let contrast = Self.bounded(values["contrast"], minimum: 0.5, maximum: 1.5),
      let saturation = Self.bounded(values["saturation"], minimum: 0, maximum: 1.8),
      let vibrance = Self.bounded(values["vibrance"], minimum: -1, maximum: 1),
      let temperature = Self.bounded(values["temperature"], minimum: -1, maximum: 1),
      let tint = Self.bounded(values["tint"], minimum: -1, maximum: 1),
      let blackLift = Self.bounded(values["blackLift"], minimum: -0.2, maximum: 0.2),
      let highlightRolloff = Self.bounded(
        values["highlightRolloff"], minimum: 0, maximum: 1
      ),
      let shadowDepth = Self.bounded(values["shadowDepth"], minimum: 0, maximum: 1),
      let midtoneBalance = Self.bounded(
        values["midtoneBalance"], minimum: -1, maximum: 1
      ),
      let colorDensity = Self.bounded(values["colorDensity"], minimum: -1, maximum: 1),
      let cyanPresence = Self.bounded(values["cyanPresence"], minimum: -1, maximum: 1),
      let magentaPresence = Self.bounded(
        values["magentaPresence"], minimum: -1, maximum: 1
      ),
      let goldPresence = Self.bounded(values["goldPresence"], minimum: -1, maximum: 1),
      let shadows = Self.parseFilterTone(values["shadows"]),
      let midtones = Self.parseFilterTone(values["midtones"]),
      let highlights = Self.parseFilterTone(values["highlights"]),
      let vignette = Self.bounded(values["vignette"], minimum: 0, maximum: 1),
      let vignetteSoftness = Self.bounded(
        values["vignetteSoftness"], minimum: 0.2, maximum: 1
      )
    else { return nil }
    return FilterGrade(
      filterID: filterID,
      intensity: intensity,
      exposure: exposure,
      contrast: contrast,
      saturation: saturation,
      vibrance: vibrance,
      temperature: temperature,
      tint: tint,
      blackLift: blackLift,
      highlightRolloff: highlightRolloff,
      shadowDepth: shadowDepth,
      midtoneBalance: midtoneBalance,
      colorDensity: colorDensity,
      cyanPresence: cyanPresence,
      magentaPresence: magentaPresence,
      goldPresence: goldPresence,
      shadows: shadows,
      midtones: midtones,
      highlights: highlights,
      vignette: vignette,
      vignetteSoftness: vignetteSoftness
    )
  }

  private static func validFilterVariants(_ value: Any?) -> Bool {
    guard
      let variants = value as? [String: Any],
      Set(variants.keys) == Set(Self.qualityLevels)
    else { return false }
    let scales = [
      "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
    ]
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any] else { return false }
      return Set(variant.keys) == Set([
        "level", "parameterOverrides", "renderScale", "framesPerSecond",
        "resourceOverrides",
      ]) && variant["level"] as? String == quality &&
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true &&
        Self.number(variant["renderScale"], equals: scales[quality]!) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue == 1 &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func parseFilterTone(_ value: Any?) -> FilterTone? {
    guard
      let tone = value as? [String: Any],
      Set(tone.keys) == Set(["color", "amount"]),
      let color = tone["color"] as? String,
      color.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil,
      let amount = Self.bounded(tone["amount"], minimum: 0, maximum: 1),
      let red = UInt8(color.dropFirst().prefix(2), radix: 16),
      let green = UInt8(color.dropFirst(3).prefix(2), radix: 16),
      let blue = UInt8(color.dropFirst(5).prefix(2), radix: 16)
    else { return nil }
    return FilterTone(
      red: Self.srgbToLinear(CGFloat(red) / 255),
      green: Self.srgbToLinear(CGFloat(green) / 255),
      blue: Self.srgbToLinear(CGFloat(blue) / 255),
      amount: amount
    )
  }

  private static func bounded(
    _ value: Any?,
    minimum: Double,
    maximum: Double
  ) -> CGFloat? {
    guard let raw = (value as? NSNumber)?.doubleValue,
          raw.isFinite, raw >= minimum, raw <= maximum else { return nil }
    return CGFloat(raw)
  }

  private static func srgbToLinear(_ value: CGFloat) -> CGFloat {
    value <= 0.04045
      ? value / 12.92
      : pow((value + 0.055) / 1.055, 2.4)
  }

  /// Exact first graph slice: one or more static, non-reactive image layers.
  /// Order, source-over alpha, transform and opacity are preserved. Other
  /// blends and image effects remain on the current continuous renderer.
  private static func parseImageDocument(
    _ document: [String: Any],
    loadImage: Bool
  ) -> [ImageLayer]? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      !layers.isEmpty,
      layers.count <= 12
    else {
      return nil
    }
    var parsed = [ImageLayer]()
    var layerIDs = Set<String>()
    for layer in layers {
      guard
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      layerIDs.insert(layerID).inserted,
      let role = layer["role"] as? String,
      ["background", "overlay"].contains(role),
      let opacity = Self.finite(layer["opacity"]),
      opacity >= 0,
      opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      let transform = Self.parseTransform(layer["transform"]),
      let frameRateBinding = layer["frameRateBinding"] as? String,
      ["staticContent", "preferred"].contains(frameRateBinding),
      let preferredFramesPerSecond =
        (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue,
      preferredFramesPerSecond >= 1,
      preferredFramesPerSecond <= 60,
      Self.number(layer["playbackRate"], equals: 1),
      let fallback = layer["fallbackPolicy"] as? String,
      ["continuousCompatibility", "unavailableBeforePlayback"].contains(fallback),
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots",
        "signalBindings", "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "media.image",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      let parameters = node["parameters"] as? [String: Any]
      else {
        return nil
      }
      let naturalReactiveLight = SceneRenderV2NaturalReactiveLightConfig.decode(
        parameters
      )
      guard
      Self.staticImageParameters(parameters) || naturalReactiveLight != nil,
      Self.validStrobeBindings(
        node["signalBindings"],
        required: naturalReactiveLight != nil
      ),
      naturalReactiveLight != nil
        ? frameRateBinding == "preferred"
        : frameRateBinding == "staticContent",
      naturalReactiveLight != nil || preferredFramesPerSecond == 1,
      let transition = node["transitionStrategy"] as? String,
      ["atomicParameters", "renderScale"].contains(transition),
      let variants = Self.parseImageVariants(
        node["qualityVariants"],
        preferredFramesPerSecond: preferredFramesPerSecond,
        reactive: naturalReactiveLight != nil
      ),
      let resources = node["resourceSlots"] as? [[String: Any]],
      resources.count == 1,
      let resource = resources.first,
      resource["slot"] as? String == "primary",
      resource["kind"] as? String == "image",
      let resourceID = resource["resourceId"] as? String,
      validToken(resourceID),
      resource["uri"] == nil
      else {
        return nil
      }
      let asset = resource["asset"] as? String
      let path = resource["path"] as? String
      guard (asset == nil) != (path == nil),
            asset == nil || asset?.isEmpty == false,
            path == nil || (path?.hasPrefix("/") == true &&
              path?.hasPrefix("//") == false) else { return nil }
      var allowedResourceKeys = Set(["slot", "resourceId", "kind"])
      if asset != nil { allowedResourceKeys.insert("asset") }
      if path != nil { allowedResourceKeys.insert("path") }
      if resource["assetPackage"] != nil { allowedResourceKeys.insert("assetPackage") }
      if resource["sha256"] != nil { allowedResourceKeys.insert("sha256") }
      guard
        Set(resource.keys) == allowedResourceKeys,
        asset != nil || resource["assetPackage"] == nil,
        resource["sha256"] == nil ||
          ((resource["sha256"] as? String)?.range(
            of: "^[0-9a-f]{64}$",
            options: .regularExpression
          ) != nil)
      else { return nil }
      var source = CIImage.empty()
      if loadImage {
        let resolvedPath: String
        if let asset {
          let package = resource["assetPackage"] as? String
          let key = package.map {
            FlutterDartProject.lookupKey(forAsset: asset, fromPackage: $0)
          } ?? FlutterDartProject.lookupKey(forAsset: asset)
          guard let bundled = Bundle.main.path(forResource: key, ofType: nil) else {
            return nil
          }
          resolvedPath = bundled
        } else {
          guard let path else { return nil }
          resolvedPath = path
        }
        guard
          FileManager.default.fileExists(atPath: resolvedPath),
          resource["sha256"] == nil ||
            Self.sha256File(URL(fileURLWithPath: resolvedPath)) ==
              resource["sha256"] as? String,
          let imageSource = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: resolvedPath) as CFURL,
            nil
          ),
          CGImageSourceGetCount(imageSource) == 1,
          let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
          decoded.width > 0,
          decoded.height > 0,
          decoded.width <= 8192,
          decoded.height <= 8192,
          decoded.width * decoded.height <= 33_554_432
        else { return nil }
        source = CIImage(cgImage: decoded)
      }
      parsed.append(ImageLayer(
        id: layerID,
        source: source,
        opacity: opacity,
        width: transform.width,
        height: transform.height,
        offsetX: transform.offsetX,
        offsetY: transform.offsetY,
        scale: transform.scale,
        rotation: transform.rotation,
        flipped: transform.flipped,
        framesPerSecondByQuality: variants.framesPerSecond,
        naturalReactiveLight: naturalReactiveLight
      ))
    }
    return parsed
  }

  /// Continuous media slice. This intentionally accepts only the exact,
  /// non-reactive media contract implemented below; reactive effects remain
  /// on their already-continuous certified backend until their node exists.
  private static func parseMediaDocument(
    _ document: [String: Any],
    resolveResource: Bool
  ) -> MediaLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      let role = layer["role"] as? String,
      ["background", "overlay"].contains(role),
      let opacity = Self.finite(layer["opacity"]),
      opacity >= 0, opacity <= 1,
      layer["blendMode"] as? String == "sourceOver",
      let transform = Self.parseTransform(layer["transform"]),
      let frameRateBinding = layer["frameRateBinding"] as? String,
      ["preferred", "sourceDriven"].contains(frameRateBinding),
      let preferredFramesPerSecond =
        (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue,
      preferredFramesPerSecond >= 1,
      preferredFramesPerSecond <= 120,
      let playbackRateNumber = layer["playbackRate"] as? NSNumber,
      playbackRateNumber.doubleValue.isFinite,
      playbackRateNumber.doubleValue > 0,
      playbackRateNumber.doubleValue <= 4,
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots",
        "signalBindings", "qualityVariants", "transitionStrategy",
      ]),
      let nodeType = node["nodeType"] as? String,
      let kind = MediaKind(rawValue: nodeType),
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      layer["alphaMode"] as? String == kind.alphaMode,
      node["transitionStrategy"] as? String == kind.transitionStrategy,
      let parameters = node["parameters"] as? [String: Any],
      let variants = Self.parseMediaVariants(
        node["qualityVariants"],
        kind: kind,
        preferredFramesPerSecond: preferredFramesPerSecond
      ),
      let resources = node["resourceSlots"] as? [[String: Any]],
      resources.count == 1,
      let resource = resources.first,
      resource["slot"] as? String == "primary",
      resource["kind"] as? String == kind.resourceKind,
      let resourceID = resource["resourceId"] as? String,
      validToken(resourceID),
      let resolved = Self.resolveMediaResource(
        resource,
        resolveResource: resolveResource
      )
    else { return nil }
    let reactiveLight = SceneRenderV2NaturalReactiveLightConfig.decode(parameters)
    let rgbGain = SceneRenderV2RGBGainConfig.decode(parameters)
    let passive = Self.validPassiveMediaParameters(parameters)
    let reactive = reactiveLight != nil || rgbGain != nil
    guard passive || reactive,
          Self.validStrobeBindings(
            node["signalBindings"],
            required: reactive
          )
    else { return nil }
    return MediaLayer(
      id: layerID,
      kind: kind,
      url: resolved.url,
      resourceIdentity: "\(resourceID)|\(resolved.identity)",
      opacity: opacity,
      width: transform.width,
      height: transform.height,
      offsetX: transform.offsetX,
      offsetY: transform.offsetY,
      scale: transform.scale,
      rotation: transform.rotation,
      flipped: transform.flipped,
      playbackRate: playbackRateNumber.floatValue,
      renderScales: variants.scales,
      framesPerSecondByQuality: variants.framesPerSecond,
      naturalReactiveLight: reactiveLight,
      rgbGain: rgbGain
    )
  }

  private static func validPassiveMediaParameters(_ value: Any?) -> Bool {
    guard let parameters = value as? [String: Any] else { return false }
    return parameters.isEmpty ||
      (Set(parameters.keys) == Set(["audioReactive"]) &&
        parameters["audioReactive"] as? Bool == false)
  }

  private static func parseMediaVariants(
    _ value: Any?,
    kind: MediaKind,
    preferredFramesPerSecond: Int
  ) -> (scales: [String: Double], framesPerSecond: [String: Int])? {
    guard
      let variants = value as? [String: Any],
      Set(variants.keys) == Set(Self.qualityLevels)
    else { return nil }
    let scales: [String: Double] = [
      "best": 1,
      "sustained": 0.8,
      "minimumFunctional": 0.6,
    ]
    let caps: [String: Int] = kind == .animatedImage
      ? ["best": 120, "sustained": 120, "minimumFunctional": 120]
      : ["best": 120, "sustained": 30, "minimumFunctional": 24]
    var frames = [String: Int]()
    for quality in Self.qualityLevels {
      guard
        let variant = variants[quality] as? [String: Any],
        Set(variant.keys) == Set([
          "level", "parameterOverrides", "renderScale", "framesPerSecond",
          "resourceOverrides",
        ]),
        variant["level"] as? String == quality,
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true,
        Self.number(variant["renderScale"], equals: scales[quality]!),
        let fps = (variant["framesPerSecond"] as? NSNumber)?.intValue,
        fps == min(preferredFramesPerSecond, caps[quality]!),
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
      else { return nil }
      frames[quality] = fps
    }
    return (scales, frames)
  }

  private static func resolveMediaResource(
    _ resource: [String: Any],
    resolveResource: Bool
  ) -> (url: URL, identity: String)? {
    var allowed = Set(["slot", "resourceId", "kind"])
    for optional in ["asset", "assetPackage", "path", "sha256"]
      where resource[optional] != nil {
      allowed.insert(optional)
    }
    guard Set(resource.keys) == allowed,
          resource["uri"] == nil else { return nil }
    let asset = resource["asset"] as? String
    let path = resource["path"] as? String
    guard (asset == nil) != (path == nil) else { return nil }
    let package = resource["assetPackage"] as? String
    guard asset != nil || package == nil else { return nil }
    let suppliedHash = resource["sha256"] as? String
    if let suppliedHash,
       suppliedHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
      return nil
    }
    let url: URL
    if let asset {
      guard !asset.isEmpty else { return nil }
      if resolveResource {
        let key = package.map {
          FlutterDartProject.lookupKey(forAsset: asset, fromPackage: $0)
        } ?? FlutterDartProject.lookupKey(forAsset: asset)
        guard let resolved = Bundle.main.path(forResource: key, ofType: nil) else {
          return nil
        }
        url = URL(fileURLWithPath: resolved)
      } else {
        url = URL(fileURLWithPath: "/v2-preflight/\(package ?? "app")/\(asset)")
      }
    } else {
      guard let path, !path.isEmpty else { return nil }
      url = URL(fileURLWithPath: path)
    }
    if resolveResource {
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      if let suppliedHash, Self.sha256File(url) != suppliedHash { return nil }
    }
    return (url, suppliedHash ?? url.path)
  }

  private static func sha256File(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    do {
      while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
        hasher.update(data: chunk)
      }
    } catch {
      return nil
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func parseRadialProfileDocument(
    _ document: [String: Any],
    resolveResource: Bool
  ) -> SceneRenderV2RadialProfileLayer? {
    guard
      Self.radialProfileKernel != nil,
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      let role = layer["role"] as? String,
      ["background", "overlay"].contains(role),
      let opacity = Self.finite(layer["opacity"]),
      opacity >= 0,
      opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      Self.identityTransform(layer["transform"]),
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 30,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots",
        "signalBindings", "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.radialProfile",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      node["transitionStrategy"] as? String == "stateReplay",
      let parameters = node["parameters"] as? [String: Any],
      Set(parameters.keys) == Set(["profileId", "audioReactive"]),
      parameters["profileId"] as? String == "chromatic_radial_collapse_v1",
      parameters["audioReactive"] as? Bool == true,
      Self.validStrobeBindings(node["signalBindings"], required: true),
      Self.validRadialProfileVariants(node["qualityVariants"]),
      let resources = node["resourceSlots"] as? [[String: Any]],
      resources.count == 1,
      let resource = resources.first,
      resource["slot"] as? String == "master0",
      resource["kind"] as? String == "profile",
      let resourceID = resource["resourceId"] as? String,
      validToken(resourceID),
      let resolved = Self.resolveMediaResource(
        resource,
        resolveResource: resolveResource
      )
    else { return nil }

    let source: CIImage
    if resolveResource {
      guard let decoded = Self.decodeRadialProfile(resolved.url) else { return nil }
      source = decoded
    } else {
      source = CIImage.empty()
    }
    return SceneRenderV2RadialProfileLayer(
      id: layerID,
      profileID: "chromatic_radial_collapse_v1",
      profileSource: source,
      resourceIdentity: "\(resourceID)|\(resolved.identity)",
      opacity: opacity,
      renderScales: Self.radialProfileRenderScales,
      framesPerSecondByQuality: Self.radialProfileFramesPerSecond
    )
  }

  private static func validRadialProfileVariants(_ value: Any?) -> Bool {
    guard let variants = value as? [String: Any],
          Set(variants.keys) == Set(Self.qualityLevels) else { return false }
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any] else { return false }
      return Set(variant.keys) == Set([
        "level", "parameterOverrides", "renderScale", "framesPerSecond",
        "resourceOverrides",
      ]) && variant["level"] as? String == quality &&
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true &&
        Self.number(
          variant["renderScale"],
          equals: Self.radialProfileRenderScales[quality]!
        ) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue ==
          Self.radialProfileFramesPerSecond[quality] &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  static func decodeRadialProfile(_ url: URL) -> CIImage? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
          data.count == Self.radialProfileByteLength else { return nil }
    let bytes = [UInt8](data)
    func uint16(_ offset: Int) -> Int {
      Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }
    func uint32(_ offset: Int) -> UInt32 {
      UInt32(bytes[offset]) |
        UInt32(bytes[offset + 1]) << 8 |
        UInt32(bytes[offset + 2]) << 16 |
        UInt32(bytes[offset + 3]) << 24
    }
    guard
      uint32(0) == 0x3150_5243,
      uint16(4) == 1,
      uint16(6) == 113,
      uint16(8) == 96,
      uint16(10) == 2,
      uint16(12) == 112,
      uint16(14) == 0
    else { return nil }

    let stopRadii = (0..<96).map { index in
      Int((733 * pow(Double(index) / 95, 1.5)).rounded())
    }
    var expanded = [UInt8](repeating: 0, count: 734 * 226 * 4)
    for row in 0..<226 {
      // Bitmap rows run top-down; the kernel addresses Core Image's bottom-up y.
      // Keep profile frame/variant indices unchanged by orienting once at decode.
      let bitmapRow = 225 - row
      var upper = 1
      for radius in 0..<734 {
        while upper < 95 && stopRadii[upper] < radius { upper += 1 }
        let lower = max(0, upper - 1)
        let lowRadius = stopRadii[lower]
        let highRadius = stopRadii[upper]
        let fraction = highRadius == lowRadius
          ? 1.0
          : Double(radius - lowRadius) / Double(highRadius - lowRadius)
        let lowOffset = 16 + (row * 96 + lower) * 4
        let highOffset = 16 + (row * 96 + upper) * 4
        let destination = (bitmapRow * 734 + radius) * 4
        let lowAlpha = Double(bytes[lowOffset + 3]) / 255
        let highAlpha = Double(bytes[highOffset + 3]) / 255
        for channel in 0..<3 {
          let low = Double(bytes[lowOffset + channel]) * lowAlpha
          let high = Double(bytes[highOffset + channel]) * highAlpha
          expanded[destination + channel] = UInt8(
            min(255, max(0, (low + (high - low) * fraction).rounded()))
          )
        }
        let alpha = Double(bytes[lowOffset + 3]) +
          (Double(bytes[highOffset + 3]) - Double(bytes[lowOffset + 3])) * fraction
        expanded[destination + 3] = UInt8(min(255, max(0, alpha.rounded())))
      }
    }
    return CIImage(
      bitmapData: Data(expanded),
      bytesPerRow: 734 * 4,
      size: CGSize(width: 734, height: 226),
      format: .RGBA8,
      colorSpace: Self.outputColorSpace
    )
  }

  /// Exact installed/default strobe programs. Arbitrary modes and shader
  /// code are deliberately not part of this node contract.
  private static func parseStrobeDocument(_ document: [String: Any]) -> StrobeLayer? {
    guard
      Set(document.keys) == Set(["schemaVersion", "sceneId", "layers"]),
      (document["schemaVersion"] as? NSNumber)?.intValue == 2,
      let sceneID = document["sceneId"] as? String,
      validToken(sceneID),
      let layers = document["layers"] as? [[String: Any]],
      layers.count == 1,
      let layer = layers.first,
      Set(layer.keys) == Set([
        "id", "role", "node", "opacity", "alphaMode", "blendMode", "transform",
        "frameRateBinding", "preferredFramesPerSecond", "playbackRate", "fallbackPolicy",
      ]),
      let layerID = layer["id"] as? String,
      validToken(layerID),
      let role = layer["role"] as? String,
      ["background", "overlay"].contains(role),
      let opacity = Self.finite(layer["opacity"]),
      opacity >= 0,
      opacity <= 1,
      layer["alphaMode"] as? String == "normal",
      layer["blendMode"] as? String == "sourceOver",
      Self.identityTransform(layer["transform"]),
      layer["frameRateBinding"] as? String == "preferred",
      (layer["preferredFramesPerSecond"] as? NSNumber)?.intValue == 60,
      Self.number(layer["playbackRate"], equals: 1),
      layer["fallbackPolicy"] as? String == "continuousCompatibility",
      let node = layer["node"] as? [String: Any],
      Set(node.keys) == Set([
        "nodeType", "nodeVersion", "parameters", "resourceSlots",
        "signalBindings", "qualityVariants", "transitionStrategy",
      ]),
      node["nodeType"] as? String == "effect.strobe",
      (node["nodeVersion"] as? NSNumber)?.intValue == 1,
      (node["resourceSlots"] as? [Any])?.isEmpty == true,
      node["transitionStrategy"] as? String == "cadenceLocked",
      let parameters = node["parameters"] as? [String: Any],
      let programID = parameters["programId"] as? String,
      let program = StrobeProgram(rawValue: programID),
      Self.validStrobeParameters(parameters, program: program),
      Self.validStrobeBindings(node["signalBindings"], required: program.audioReactive),
      Self.validStrobeVariants(node["qualityVariants"])
    else {
      return nil
    }
    guard let options = Self.strobeOptions(parameters, program: program) else { return nil }
    return StrobeLayer(id: layerID, program: program, opacity: opacity, options: options)
  }

  private static func validStrobeParameters(
    _ parameters: [String: Any],
    program: StrobeProgram
  ) -> Bool {
    strobeOptions(parameters, program: program) != nil
  }

  private static func strobeOptions(
    _ parameters: [String: Any], program: StrobeProgram
  ) -> StrobeOptions? {
    var keys = Set(["programId", "audioReactive"])
    if parameters["mode"] != nil { keys.insert("mode") }
    if parameters["options"] != nil { keys.insert("options") }
    guard Set(parameters.keys) == keys,
          parameters["audioReactive"] as? Bool == program.audioReactive
    else { return nil }
    if parameters["mode"] != nil && !(parameters["mode"] is String) { return nil }
    let mode = parameters["mode"] as? String ?? ""
    let raw: [String: Any]
    if let value = parameters["options"] {
      guard let options = value as? [String: Any] else { return nil }
      raw = options
    } else { raw = [:] }
    var result = StrobeOptions(intervalMicros: program.logicalIntervalMicros)
    result.modeIdentity = mode.isEmpty ? "default" : mode
    var booleans = Set<String>()
    var ranges = [String: ClosedRange<Double>]()
    switch program {
    case .backgroundBlackWhite, .backgroundColorLights:
      guard mode.isEmpty || mode == "default" else { return nil }
      booleans = ["Show Black Screen", "Smooth Transitions"]
      ranges = ["Velocity": 10...1_000]
    case .transparentBlackWhite:
      booleans = ["Smooth Transitions"]
      ranges = ["Velocity": 10...500]
      switch mode {
      case "", "default": result.intervalMicros = 50_000
      case "fast": result.intervalMicros = 50_000; result.smooth = true
      case "slow": result.intervalMicros = 500_000
      case "rainbow", "bright rainbow":
        result.intervalMicros = 100_000
        result.smooth = true
        result.rainbow = true
        result.brightRainbow = mode == "bright rainbow"
      default: return nil
      }
      result.showBlack = false
    case .backgroundSimpleDisco:
      guard ["", "default", "smooth"].contains(mode) else { return nil }
      result.smooth = mode == "smooth"
      booleans = ["Smooth"]
    case .backgroundProColorful:
      booleans = ["Smooth Transitions", "Rotation Mode", "Scale Mode", "Gradient Mode", "Spark Mode"]
      ranges = ["Speed": 0.1...10, "Brightness": 0.1...1]
      switch mode {
      case "", "default", "Estándar": break
      case "Rotación": result.rotation = true
      case "Escala": result.scale = true
      case "Gradiente": result.gradient = true
      case "Chispa": result.spark = true
      default: return nil
      }
    case .transparentProStrobe:
      booleans = ["Smooth Transitions", "Intense Mode"]
      ranges = ["Speed": 0.1...10, "Brightness": 0.1...1, "Flash Duration": 0.1...1, "Mode": 0...4]
      switch mode {
      case "", "default", "intense": result.intense = true
      case "smooth": result.smooth = true
      case "transparent white": result.transparentWhite = true
      case "transparent black": result.transparentBlack = true
      default: return nil
      }
    }
    guard Set(raw.keys).isSubset(of: booleans.union(ranges.keys)) else { return nil }
    for key in booleans where raw[key] != nil {
      guard let value = raw[key] as? NSNumber,
            CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
    }
    for (key, range) in ranges where raw[key] != nil {
      guard let number = raw[key] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite, range.contains(number.doubleValue)
      else { return nil }
    }
    // Legacy selector snapshots are actions, not persistent overrides. Apply
    // that action first, then the individually saved values below. New strict
    // documents carry the resulting mode/values without a retained Mode action.
    if let value = raw["Mode"] as? NSNumber {
      guard value.doubleValue == Double(value.intValue) else { return nil }
      switch value.intValue {
      case 0:
        result.modeIdentity = "default"
        result.smooth = false; result.intense = true
        result.transparentWhite = false; result.transparentBlack = false
        result.speed = 1; result.brightness = 1
      case 1:
        result.modeIdentity = "smooth"
        result.smooth = true; result.intense = false
        result.transparentWhite = false; result.transparentBlack = false
      case 2:
        result.modeIdentity = "intense"
        result.smooth = false; result.intense = true
        result.transparentWhite = false; result.transparentBlack = false
      case 3:
        result.modeIdentity = "transparent white"
        result.transparentWhite = true; result.transparentBlack = false
      case 4:
        result.modeIdentity = "transparent black"
        result.transparentBlack = true; result.transparentWhite = false
      default: return nil
      }
    }
    if let value = raw["Velocity"] as? NSNumber {
      let milliseconds = program == .transparentBlackWhite
        ? (510 - value.doubleValue).rounded()
        : 1_000 - (pow(value.doubleValue / 1_000, 0.3) * 1_000).rounded()
      result.intervalMicros = Int64(max(6, milliseconds)) * 1_000
    }
    result.smooth = raw["Smooth Transitions"] as? Bool ?? raw["Smooth"] as? Bool ?? result.smooth
    result.showBlack = raw["Show Black Screen"] as? Bool ?? result.showBlack
    result.rotation = raw["Rotation Mode"] as? Bool ?? result.rotation
    result.scale = raw["Scale Mode"] as? Bool ?? result.scale
    result.gradient = raw["Gradient Mode"] as? Bool ?? result.gradient
    result.spark = raw["Spark Mode"] as? Bool ?? result.spark
    result.intense = raw["Intense Mode"] as? Bool ?? result.intense
    result.speed = (raw["Speed"] as? NSNumber)?.doubleValue ?? result.speed
    result.brightness = (raw["Brightness"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? result.brightness
    result.flashDuration = (raw["Flash Duration"] as? NSNumber)?.doubleValue ?? result.flashDuration
    return result
  }

  private static func validStrobeBindings(_ value: Any?, required: Bool) -> Bool {
    guard let bindings = value as? [[String: Any]] else { return false }
    if !required { return bindings.isEmpty }
    guard bindings.count == 1, let binding = bindings.first else { return false }
    return Set(binding.keys) == Set(["signal", "target", "scale", "bias"]) &&
      binding["signal"] as? String == "frame.v2" &&
      binding["target"] as? String == "runtime.signalFrame" &&
      Self.number(binding["scale"], equals: 1) &&
      Self.number(binding["bias"], equals: 0)
  }

  private static func validStrobeVariants(_ value: Any?) -> Bool {
    guard
      let variants = value as? [String: Any],
      Set(variants.keys) == Set(Self.qualityLevels)
    else { return false }
    let scales = Self.strobeRenderScales
    return Self.qualityLevels.allSatisfy { quality in
      guard let variant = variants[quality] as? [String: Any] else { return false }
      return Set(variant.keys) == Set([
        "level", "parameterOverrides", "renderScale", "framesPerSecond",
        "resourceOverrides",
      ]) && variant["level"] as? String == quality &&
        (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true &&
        Self.number(variant["renderScale"], equals: scales[quality]!) &&
        (variant["framesPerSecond"] as? NSNumber)?.intValue == 60 &&
        (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
    }
  }

  private static func identityTransform(_ value: Any?) -> Bool {
    guard let transform = value as? [String: Any] else { return false }
    return Set(transform.keys) == Set([
      "width", "height", "offsetX", "offsetY", "scale", "rotation", "flipped",
    ]) && Self.number(transform["width"], equals: 1) &&
      Self.number(transform["height"], equals: 1) &&
      Self.number(transform["offsetX"], equals: 0) &&
      Self.number(transform["offsetY"], equals: 0) &&
      Self.number(transform["scale"], equals: 1) &&
      Self.number(transform["rotation"], equals: 0) &&
      transform["flipped"] as? Bool == false
  }

  private static func parseImageVariants(
    _ value: Any?,
    preferredFramesPerSecond: Int,
    reactive: Bool
  ) -> (scales: [String: Double], framesPerSecond: [String: Int])? {
    guard
      let variants = value as? [String: Any],
      Set(variants.keys) == Set(Self.qualityLevels)
    else { return nil }
    let scales = Self.imageRenderScales
    let frameCaps = [
      "best": 60,
      "sustained": 30,
      "minimumFunctional": 24,
    ]
    var frames = [String: Int]()
    for quality in Self.qualityLevels {
      guard let variant = variants[quality] as? [String: Any],
            Set(variant.keys) == Set([
              "level", "parameterOverrides", "renderScale", "framesPerSecond",
              "resourceOverrides",
            ]),
            variant["level"] as? String == quality,
            (variant["parameterOverrides"] as? [String: Any])?.isEmpty == true,
            Self.number(variant["renderScale"], equals: scales[quality]!),
            let framesPerSecond =
              (variant["framesPerSecond"] as? NSNumber)?.intValue,
            framesPerSecond == (reactive
              ? min(preferredFramesPerSecond, frameCaps[quality]!)
              : 1),
            (variant["resourceOverrides"] as? [String: Any])?.isEmpty == true
      else { return nil }
      frames[quality] = framesPerSecond
    }
    return (scales, frames)
  }

  private static func staticImageParameters(_ value: Any?) -> Bool {
    guard let parameters = value as? [String: Any] else { return false }
    return parameters.isEmpty ||
      (Set(parameters.keys) == Set(["audioReactive"]) &&
        parameters["audioReactive"] as? Bool == false)
  }

  private static func parseTransform(_ value: Any?) -> (
    width: CGFloat,
    height: CGFloat,
    offsetX: CGFloat,
    offsetY: CGFloat,
    scale: CGFloat,
    rotation: CGFloat,
    flipped: Bool
  )? {
    guard let transform = value as? [String: Any] else { return nil }
    guard
      Set(transform.keys) == Set([
        "width", "height", "scale", "rotation", "offsetX", "offsetY", "flipped",
      ]),
      let width = Self.finite(transform["width"]),
      let height = Self.finite(transform["height"]),
      let scale = Self.finite(transform["scale"]),
      let rotation = Self.finite(transform["rotation"]),
      let offsetX = Self.finite(transform["offsetX"]),
      let offsetY = Self.finite(transform["offsetY"]),
      let flipped = transform["flipped"] as? Bool,
      width > 0,
      height > 0,
      scale > 0,
      width <= 16,
      height <= 16,
      scale <= 16,
      abs(offsetX) <= 16,
      abs(offsetY) <= 16,
      abs(rotation) <= 100
    else { return nil }
    return (width, height, offsetX, offsetY, scale, rotation, flipped)
  }

  private static func aspectFill(_ image: CIImage, targetRect: CGRect) -> CIImage {
    let extent = image.extent
    guard extent.width > 0, extent.height > 0 else {
      return image.cropped(to: targetRect)
    }
    let scale = max(
      targetRect.width / extent.width,
      targetRect.height / extent.height
    )
    let scaled = image.transformed(
      by: CGAffineTransform(scaleX: scale, y: scale)
    )
    return scaled.transformed(
      by: CGAffineTransform(
        translationX: targetRect.midX - scaled.extent.midX,
        y: targetRect.midY - scaled.extent.midY
      )
    ).cropped(to: targetRect)
  }

  private static func renderMediaLayer(
    _ layer: MediaLayer,
    source: CIImage,
    target: CGRect
  ) -> CIImage {
    let width = target.width * layer.width
    let height = target.height * layer.height
    let layerRect = CGRect(
      x: target.midX - width * 0.5 + target.width * layer.offsetX,
      y: target.midY - height * 0.5 - target.height * layer.offsetY,
      width: width,
      height: height
    )
    var rendered = Self.aspectFill(source, targetRect: layerRect)
    let center = CGPoint(x: layerRect.midX, y: layerRect.midY)
    var affine = CGAffineTransform(translationX: center.x, y: center.y)
    affine = affine.rotated(by: -layer.rotation)
    affine = affine.scaledBy(
      x: layer.flipped ? -layer.scale : layer.scale,
      y: layer.scale
    )
    affine = affine.translatedBy(x: -center.x, y: -center.y)
    rendered = rendered.transformed(by: affine).cropped(to: target)
    if layer.opacity < 0.999_999 {
      rendered = rendered.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity),
        ]
      )
    }
    return rendered
  }

  static func renderRadialProfileLayer(
    _ layer: SceneRenderV2RadialProfileLayer,
    state: SceneRenderV2RadialProfileState,
    target: CGRect,
    reducedMotion: Bool = false
  ) throws -> CIImage {
    guard state.active, state.profileFrame >= 2, state.profileFrame < 112 else {
      return CIImage(
        color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
      ).cropped(to: target)
    }
    guard let kernel = Self.radialProfileKernel else {
      throw RuntimeError("radial_profile_kernel_unavailable")
    }
    let row = state.profileFrame + (state.major ? 113 : 0)
    guard var rendered = kernel.apply(
      extent: target,
      roiCallback: { _, _ in layer.profileSource.extent },
      arguments: [
        layer.profileSource,
        CIVector(x: target.origin.x, y: target.origin.y),
        CIVector(x: target.width, y: target.height),
        CGFloat(row),
        reducedMotion ? 0.62 : 1.0,
        reducedMotion ? 0.72 : 1.0,
      ]
    ) else {
      throw RuntimeError("radial_profile_render_failed")
    }
    rendered = rendered.cropped(to: target)
    if layer.opacity < 0.999_999 {
      rendered = rendered.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity),
        ]
      )
    }
    return rendered
  }

  private static func renderRadialWarpLayer(
    graphics: GraphicsResources?,
    _ layer: SceneRenderV2RadialWarpLayer,
    state: SceneRenderV2RadialWarpState,
    quality: String,
    target: CGRect,
    device: MTLDevice,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> CIImage {
    guard
      let renderer = graphics?.radialWarpRenderer,
      let count = layer.particleCountsByQuality[quality],
      let bloom = layer.bloomByQuality[quality]
    else { throw RuntimeError("radial_warp_renderer_unavailable") }
    let texture = try renderer.render(
      width: Int(target.width),
      height: Int(target.height),
      count: count,
      bloom: bloom,
      opacity: Float(layer.opacity),
      state: state,
      outputAllocator: outputAllocator
    )
    guard var image = CIImage(
      mtlTexture: texture,
      options: [.colorSpace: Self.outputColorSpace]
    ) else { throw RuntimeError("radial_warp_image_failed") }
    // CIImage treats an MTL texture as vertically reflected relative to the
    // SceneSurface coordinate system. Normalize it before graph composition.
    image = image.transformed(
      by: CGAffineTransform(translationX: 0, y: target.height)
        .scaledBy(x: 1, y: -1)
    ).cropped(to: target)
    _ = device
    return image
  }

  private static func renderSnowfallLayer(
    graphics: GraphicsResources?,
    _ layer: SceneRenderV2SnowfallLayer,
    state: SceneRenderV2SnowfallState,
    quality: String,
    pointScale: Float,
    target: CGRect,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> CIImage {
    guard
      let renderer = graphics?.snowfallRenderer,
      let count = layer.particleCountsByQuality[quality]
    else { throw RuntimeError("snowfall_renderer_unavailable") }
    let texture = try renderer.render(
      width: Int(target.width),
      height: Int(target.height),
      count: count,
      pointScale: pointScale,
      opacity: Float(layer.opacity),
      particleData: layer.particleData,
      state: state,
      outputAllocator: outputAllocator
    )
    guard var image = CIImage(
      mtlTexture: texture,
      options: [.colorSpace: Self.outputColorSpace]
    ) else { throw RuntimeError("snowfall_image_failed") }
    image = image.transformed(
      by: CGAffineTransform(translationX: 0, y: target.height)
        .scaledBy(x: 1, y: -1)
    ).cropped(to: target)
    return image
  }

  private static func renderPaintedStarlightLayer(
    graphics: GraphicsResources?,
    _ layer: SceneRenderV2PaintedStarlightLayer,
    state: SceneRenderV2PaintedStarlightState,
    quality: String,
    target: CGRect,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> CIImage {
    guard
      let renderer = graphics?.paintedStarlightRenderer,
      let intensityScale = layer.intensityScaleByQuality[quality]
    else { throw RuntimeError("painted_starlight_renderer_unavailable") }
    let texture = try renderer.render(
      width: Int(target.width),
      height: Int(target.height),
      opacity: Float(layer.opacity),
      intensityScale: intensityScale,
      state: state,
      outputAllocator: outputAllocator
    )
    guard var image = CIImage(
      mtlTexture: texture,
      options: [.colorSpace: Self.outputColorSpace]
    ) else { throw RuntimeError("painted_starlight_image_failed") }
    image = image.transformed(
      by: CGAffineTransform(translationX: 0, y: target.height)
        .scaledBy(x: 1, y: -1)
    ).cropped(to: target)
    return image
  }

  private static func renderMagicStarsLayer(
    graphics: GraphicsResources?,
    _ layer: SceneRenderV2MagicStarsLayer,
    state: SceneRenderV2MagicStarsState,
    quality: String,
    pointScale: Float,
    target: CGRect,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> CIImage {
    guard
      let renderer = graphics?.magicStarsRenderer,
      let intensityScale = layer.intensityScaleByQuality[quality]
    else { throw RuntimeError("magic_stars_renderer_unavailable") }
    let texture = try renderer.render(
      width: Int(target.width),
      height: Int(target.height),
      opacity: Float(layer.opacity),
      intensityScale: Float(intensityScale),
      pointScale: pointScale,
      state: state,
      outputAllocator: outputAllocator
    )
    guard var image = CIImage(
      mtlTexture: texture,
      options: [.colorSpace: Self.outputColorSpace]
    ) else { throw RuntimeError("magic_stars_image_failed") }
    image = image.transformed(
      by: CGAffineTransform(translationX: 0, y: target.height)
        .scaledBy(x: 1, y: -1)
    ).cropped(to: target)
    return image
  }

  private static func renderBlueSkyLayer(
    _ layer: SceneRenderV2BlueSkyLayer,
    target: CGRect
  ) -> CIImage {
    let gradient = CIFilter(
      name: "CILinearGradient",
      parameters: [
        "inputPoint0": CIVector(x: target.midX, y: target.minY),
        "inputPoint1": CIVector(x: target.midX, y: target.maxY),
        "inputColor0": CIColor(
          red: Double(0x31) / 255,
          green: Double(0x1b) / 255,
          blue: Double(0x92) / 255
        ),
        "inputColor1": CIColor(red: 0, green: 0, blue: 0),
      ]
    )?.outputImage?.cropped(to: target) ?? CIImage(
      color: CIColor(red: 0, green: 0, blue: 0)
    ).cropped(to: target)
    guard layer.opacity < 0.999_999 else { return gradient }
    return gradient.applyingFilter(
      "CIColorMatrix",
      parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity)]
    )
  }

  private static func renderMagicMoonLayer(
    _ layer: SceneRenderV2MagicMoonLayer,
    state: SceneRenderV2MagicMoonState,
    target: CGRect
  ) throws -> CIImage {
    guard let kernel = Self.magicMoonAuraKernel else {
      throw RuntimeError("magic_moon_kernel_unavailable")
    }
    let progress = state.progress.truncatingRemainder(dividingBy: 1)
    let center = CGPoint(
      x: target.minX + target.width * (1.26 - progress * 1.52),
      y: target.minY + target.height *
        (1 - (0.28 - Foundation.sin(progress * .pi) * 0.11))
    )
    let radius = min(target.width, target.height) * 0.052
    guard let aura = kernel.apply(
      extent: target,
      arguments: [
        CIVector(x: target.minX, y: target.minY),
        CIVector(x: center.x, y: center.y),
        radius,
        layer.opacity,
      ]
    ) else { throw RuntimeError("magic_moon_aura_failed") }
    let textureRect = CGRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    )
    let sourceExtent = layer.texture.extent
    guard sourceExtent.width > 0, sourceExtent.height > 0 else {
      throw RuntimeError("magic_moon_texture_missing")
    }
    var texture = layer.texture.transformed(
      by: CGAffineTransform(
        scaleX: textureRect.width / sourceExtent.width,
        y: textureRect.height / sourceExtent.height
      )
    )
    texture = texture.transformed(
      by: CGAffineTransform(
        translationX: textureRect.minX - texture.extent.minX,
        y: textureRect.minY - texture.extent.minY
      )
    ).cropped(to: target)
    texture = texture.applyingFilter(
      "CIColorMatrix",
      parameters: [
        "inputAVector": CIVector(
          x: 0, y: 0, z: 0, w: 0.5 * layer.opacity
        ),
      ]
    )
    return texture.applyingFilter(
      "CISourceOverCompositing",
      parameters: [kCIInputBackgroundImageKey: aura]
    ).cropped(to: target)
  }

  private static func renderRadiantEmissionLayer(
    _ layer: SceneRenderV2RadiantEmissionLayer,
    state: SceneRenderV2RadiantEmissionState,
    quality: String,
    target: CGRect,
    reducedMotion: Bool = false
  ) throws -> CIImage {
    guard
      let kernel = Self.radiantEmissionKernel,
      let qualityScale = layer.intensityScaleByQuality[quality],
      let image = kernel.apply(
        extent: target,
        arguments: [
          CIVector(x: target.minX, y: target.minY),
          CIVector(x: target.width, y: target.height),
          CIVector(x: layer.centerX, y: layer.centerY),
          state.flow,
          state.bass,
          state.pulseA.progress,
          state.pulseA.strength,
          state.pulseB.progress,
          state.pulseB.strength,
          layer.intensity * qualityScale,
          layer.opacity,
          reducedMotion ? 0.0 : 1.0,
        ]
      )
    else { throw RuntimeError("radiant_emission_render_failed") }
    return image.cropped(to: target)
  }

  private static func renderRainbowWaterfallLayer(
    _ layer: SceneRenderV2RainbowWaterfallLayer,
    state: SceneRenderV2RainbowWaterfallState,
    target: CGRect,
    reducedMotion: Bool = false
  ) throws -> CIImage {
    guard
      let kernel = Self.rainbowWaterfallKernel,
      let image = kernel.apply(
        extent: target,
        arguments: [
          CIVector(x: target.minX, y: target.minY),
          CIVector(x: target.width, y: target.height),
          state.phase,
          state.bass,
          state.body,
          state.pulse,
          state.energy,
          state.flow,
          layer.opacity,
          reducedMotion ? 0.35 : 1.0,
        ]
      )
    else { throw RuntimeError("rainbow_waterfall_render_failed") }
    return image.cropped(to: target)
  }

  private static func renderNeonPulseLayer(
    graphics: GraphicsResources?,
    _ layer: SceneRenderV2NeonPulseLayer,
    state: SceneRenderV2NeonPulseState,
    quality: String,
    pointScale: Float,
    target: CGRect,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> CIImage {
    guard
      let renderer = graphics?.neonPulseRenderer,
      let maximumParticles = layer.maximumParticlesByQuality[quality]
    else { throw RuntimeError("neon_pulse_renderer_unavailable") }
    let texture = try renderer.render(
      width: Int(target.width),
      height: Int(target.height),
      opacity: Float(layer.opacity),
      pointScale: pointScale,
      maximumParticles: maximumParticles,
      state: state,
      outputAllocator: outputAllocator
    )
    guard var image = CIImage(
      mtlTexture: texture,
      options: [.colorSpace: Self.outputColorSpace]
    ) else { throw RuntimeError("neon_pulse_image_failed") }
    image = image.transformed(
      by: CGAffineTransform(translationX: 0, y: target.height)
        .scaledBy(x: 1, y: -1)
    ).cropped(to: target)
    return image
  }

  private static func renderEmbeddedScreenLayer(
    graphics: GraphicsResources?,
    _ layer: SceneRenderV2EmbeddedScreenLayer,
    state: SceneRenderV2EmbeddedScreenState,
    quality: String,
    target: CGRect,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> CIImage {
    guard let renderer = graphics?.embeddedScreenRenderer else {
      throw RuntimeError("embedded_screen_renderer_unavailable")
    }
    let layerWidth = target.width * layer.width
    let layerHeight = target.height * layer.height
    let layerRect = CGRect(
      x: target.midX - layerWidth * 0.5 + target.width * layer.offsetX,
      y: target.midY - layerHeight * 0.5 - target.height * layer.offsetY,
      width: layerWidth,
      height: layerHeight
    )
    var background = Self.aspectFill(layer.source, targetRect: layerRect)
    let center = CGPoint(x: layerRect.midX, y: layerRect.midY)
    var affine = CGAffineTransform(translationX: center.x, y: center.y)
    affine = affine.rotated(by: -layer.rotation)
    affine = affine.scaledBy(
      x: layer.flipped ? -layer.scale : layer.scale,
      y: layer.scale
    )
    affine = affine.translatedBy(x: -center.x, y: -center.y)
    background = background.transformed(by: affine).cropped(to: target)
    if layer.opacity < 0.999_999 {
      background = background.applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity),
        ]
      )
    }
    let points = Self.embeddedScreenRenderCorners([
      layer.topLeft,
      layer.topRight,
      layer.bottomRight,
      layer.bottomLeft,
    ], layerRect: layerRect, transform: affine, target: target)
    let texture = try renderer.render(
      width: Int(target.width),
      height: Int(target.height),
      corners: points,
      layer: layer,
      state: state,
      quality: quality,
      outputAllocator: outputAllocator
    )
    guard var overlay = CIImage(
      mtlTexture: texture,
      options: [.colorSpace: Self.outputColorSpace]
    ) else { throw RuntimeError("embedded_screen_image_failed") }
    overlay = overlay.transformed(
      by: CGAffineTransform(translationX: 0, y: target.height)
        .scaledBy(x: 1, y: -1)
    ).cropped(to: target)
    return overlay.applyingFilter(
      "CISourceOverCompositing",
      parameters: [kCIInputBackgroundImageKey: background]
    ).cropped(to: target)
  }

  private static func renderWaveformLayer(
    graphics: GraphicsResources?,
    _ layer: SceneRenderV2WaveformLayer,
    state: SceneRenderV2WaveformState,
    quality: String,
    pointScale: Float,
    target: CGRect,
    outputAllocator: SceneSurfaceNativeOutputAllocator? = nil
  ) throws -> CIImage {
    guard let renderer = graphics?.waveformRenderer else {
      throw RuntimeError("waveform_renderer_unavailable")
    }
    let texture = try renderer.render(
      width: Int(target.width),
      height: Int(target.height),
      layer: layer,
      state: state,
      quality: quality,
      pointScale: pointScale,
      outputAllocator: outputAllocator
    )
    guard var image = CIImage(
      mtlTexture: texture,
      options: [.colorSpace: Self.outputColorSpace]
    ) else { throw RuntimeError("waveform_image_failed") }
    image = image.transformed(
      by: CGAffineTransform(translationX: 0, y: target.height)
        .scaledBy(x: 1, y: -1)
    ).cropped(to: target)
    return image
  }

  private static func embeddedScreenRenderCorners(
    _ points: [SceneRenderV2EmbeddedScreenPoint],
    layerRect: CGRect,
    transform: CGAffineTransform,
    target: CGRect
  ) -> [SIMD2<Float>] {
    points.map { point in
      let pixel = CGPoint(
        x: layerRect.minX + CGFloat(point.x) * layerRect.width,
        y: layerRect.maxY - CGFloat(point.y) * layerRect.height
      ).applying(transform)
      return SIMD2<Float>(
        Float((pixel.x - target.minX) / target.width),
        Float((target.maxY - pixel.y) / target.height)
      )
    }
  }

  private static func validContinuity(_ value: Any?) -> Bool {
    guard
      let value = value as? [String: Any],
      Set(value.keys) == Set([
        "hostTimeMicros", "mediaPtsMicros", "sessionSeed", "audioSessionId",
        "audioSequence", "eventSerials", "proceduralStateByLayer",
      ]),
      integer(value["hostTimeMicros"], minimum: 0) != nil,
      integer(value["mediaPtsMicros"], minimum: 0) != nil,
      let seed = integer(value["sessionSeed"], minimum: 0),
      seed <= Int64(Int32.max),
      integer(value["audioSessionId"], minimum: 0) != nil,
      integer(value["audioSequence"], minimum: -1) != nil,
      let serials = value["eventSerials"] as? [String: Any],
      let procedural = value["proceduralStateByLayer"] as? [String: Any]
    else { return false }
    var proceduralBytes = 0
    for (key, raw) in procedural {
      guard
        validToken(key),
        let bytes = (raw as? FlutterStandardTypedData)?.data,
        bytes.count <= 16 * 1024
      else { return false }
      proceduralBytes += bytes.count
    }
    return proceduralBytes <= 64 * 1024 && serials.allSatisfy { key, raw in
      validToken(key) && integer(raw, minimum: -1) != nil
    }
  }

  private static func integer(_ value: Any?, minimum: Int64) -> Int64? {
    guard let number = value as? NSNumber else { return nil }
    let double = number.doubleValue
    guard double.isFinite, double.rounded() == double else { return nil }
    let integer = number.int64Value
    return integer >= minimum ? integer : nil
  }

  private static func finitePositive(_ value: Any?) -> Double? {
    guard let value = (value as? NSNumber)?.doubleValue,
          value.isFinite, value > 0 else { return nil }
    return value
  }

  private static func finite(_ value: Any?) -> CGFloat? {
    guard let value = (value as? NSNumber)?.doubleValue, value.isFinite else {
      return nil
    }
    return CGFloat(value)
  }

  private static func percentile(_ values: [Int], fraction: Double) -> Int {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let rank = max(1, Int(ceil(Double(sorted.count) * fraction)))
    return sorted[min(sorted.count - 1, rank - 1)]
  }

  private static func number(_ value: Any?, equals expected: Double) -> Bool {
    guard let value = (value as? NSNumber)?.doubleValue else { return false }
    return value.isFinite && value == expected
  }

  private func validToken(_ value: String) -> Bool { Self.validToken(value) }
  private static func validToken(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 128 &&
      value.unicodeScalars.allSatisfy { $0.value >= 0x20 }
  }

  private func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private struct RuntimeError: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
    var isBackpressure: Bool { code == "pixel_buffer_backpressure" }
  }

  private var rejectedTransition: [String: Any?] { Self.rejectedTransition }
  private static let rejectedTransition: [String: Any?] = [
    "accepted": false,
    "observedBackend": nil,
  ]
  private static let qualityLevels = [
    "best", "sustained", "minimumFunctional",
  ]
  private static let mediaPrerollTimeoutMilliseconds = 2_000
  private static let maximumPixelBuffersPerOutputPool = 8
  private static let signalPresentationTimeoutNanos: UInt64 = 1_000_000_000
  private static let recoveryPresentationTimeoutNanos: UInt64 = 2_000_000_000
  private static let flashVisibleDurationNanos: UInt64 = 100_000_000
  private static let flashHidePresentationTimeoutNanos: UInt64 = 500_000_000
  private static let imageRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let strobeRenderScales = [
    "best": 1.0, "sustained": 0.85, "minimumFunctional": 0.7,
  ]
  private static let radialProfileRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let radialProfileFramesPerSecond = [
    "best": 30, "sustained": 24, "minimumFunctional": 20,
  ]
  private static let radialWarpRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let radialWarpFramesPerSecond = [
    "best": 30, "sustained": 24, "minimumFunctional": 20,
  ]
  private static let radialWarpParticleCounts = [
    "best": 460, "sustained": 360, "minimumFunctional": 260,
  ]
  private static let radialWarpBloom = [
    "best": true, "sustained": true, "minimumFunctional": false,
  ]
  private static let radialWarpPalette: [Int64] = [
    0xFF30D8FF, 0xFF2B5CFF, 0xFFF4FBFF,
    0xFFFFB33A, 0xFF8BEA55, 0xFFFF6BCB,
  ]
  private static let snowfallRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let snowfallFramesPerSecond = [
    "best": 30, "sustained": 24, "minimumFunctional": 20,
  ]
  private static let snowfallParticleCounts = [
    "best": 144, "sustained": 112, "minimumFunctional": 84,
  ]
  private static let snowfallStrokeWidths = [0.65, 1.15, 1.85, 2.7]
  private static let snowfallColors: [Int64] = [
    0x70DCEEFF, 0x94E8F4FF, 0xB8F4FAFF, 0xD8FFFFFF,
  ]
  private static let paintedStarlightRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let paintedStarlightFramesPerSecond = [
    "best": 30, "sustained": 30, "minimumFunctional": 24,
  ]
  private static let paintedStarlightIntensityScales = [
    "best": 1.0, "sustained": 0.82, "minimumFunctional": 0.65,
  ]
  private static let magicStarsRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let magicStarsFramesPerSecond = [
    "best": 60, "sustained": 30, "minimumFunctional": 24,
  ]
  private static let magicStarsIntensityScales = [
    "best": 1.0, "sustained": 0.82, "minimumFunctional": 0.65,
  ]
  private static let passiveShaderRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let magicMoonFramesPerSecond = [
    "best": 1, "sustained": 1, "minimumFunctional": 1,
  ]
  private static let radiantEmissionRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let radiantEmissionFramesPerSecond = [
    "best": 30, "sustained": 30, "minimumFunctional": 24,
  ]
  private static let radiantEmissionIntensityScales = [
    "best": 1.0, "sustained": 0.82, "minimumFunctional": 0.72,
  ]
  private static let rainbowWaterfallRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let rainbowWaterfallFramesPerSecond = [
    "best": 30, "sustained": 30, "minimumFunctional": 24,
  ]
  private static let neonPulseRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let neonPulseFramesPerSecond = [
    "best": 60, "sustained": 30, "minimumFunctional": 24,
  ]
  private static let neonPulseMaximumParticles = [
    "best": 200, "sustained": 140, "minimumFunctional": 80,
  ]
  private static let embeddedScreenRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let embeddedScreenFramesPerSecond = [
    "best": 30, "sustained": 24, "minimumFunctional": 20,
  ]
  private static let embeddedScreenRingCounts = [
    "best": 4, "sustained": 3, "minimumFunctional": 2,
  ]
  private static let embeddedScreenRayCounts = [
    "best": 10, "sustained": 6, "minimumFunctional": 0,
  ]
  private static let embeddedScreenSpectrumSamples = [
    "best": 17, "sustained": 13, "minimumFunctional": 9,
  ]
  private static let waveformRenderScales = [
    "best": 1.0, "sustained": 0.75, "minimumFunctional": 0.5,
  ]
  private static let waveformFramesPerSecond = [
    "best": 24, "sustained": 20, "minimumFunctional": 16,
  ]
  private static let waveformSampleCounts = [
    "best": 127, "sustained": 95, "minimumFunctional": 63,
  ]
  private static let waveformSpectralNodeCounts = [
    "best": 15, "sustained": 13, "minimumFunctional": 9,
  ]
  private static let waveformGlowPasses = [
    "best": 5, "sustained": 4, "minimumFunctional": 3,
  ]
  private static let radialProfileByteLength = 16 + 113 * 96 * 8
}

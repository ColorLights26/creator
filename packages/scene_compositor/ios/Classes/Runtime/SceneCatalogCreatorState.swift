import Foundation
import CoreGraphics

/// Time comes from SceneSurface and the values come from its canonical signal
/// frame. No timer, microphone, detector, normalization or extra smoothing.
final class SceneCreatorShaderState: SceneCatalogShaderState {
  private let program: SceneCreatorCatalog.Program
  private let controls: [Float]
  private let reactive: Bool
  private let seed: UInt32
  private var playing = true
  private var elapsed = 0.0
  private var lastHostTime: Double?
  private var frame: SceneRenderSignalFrameV2?
  private var pendingPulse: Float = 0
  private var eventSession: Int64 = -1
  private var lastEvents: [Int64] = [-1, -1, -1, -1]

  init?(program: String, options: [String: Any], mode: String?, reactive: Bool, seed: UInt32? = nil) {
    guard let definition = SceneCreatorCatalog.program(program), !definition.isNative, definition.allows(reactive: reactive),
      mode == nil || mode == "default",
      Set(options.keys).isSubset(of: Set(SceneCreatorCatalog.controlRanges.keys).union(["Music Reactive"]))
    else { return nil }
    var values = definition.controls
    for (key, raw) in options {
      if key == "Music Reactive" {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(),
          number.boolValue == reactive else { return nil }
      } else {
        guard let value = SceneCreatorCatalog.number(raw),
          SceneCreatorCatalog.controlRanges[key]?.contains(Float(value)) == true else { return nil }
        values[key] = Float(value)
      }
    }
    self.program = definition
    self.reactive = reactive
    self.seed = seed ?? definition.seed
    controls = ["intensity", "speed", "detail", "glow"].map { values[$0]! }
  }

  func consume(_ next: SceneRenderSignalFrameV2) -> Bool {
    guard next.dynamics.count >= 2, next.channels.count == 4, next.rhythm.count == 4 else { return false }
    let changed = frame != next
    frame = next
    if eventSession != next.sessionId {
      eventSession = next.sessionId
      lastEvents = [-1, -1, -1, -1]
      pendingPulse = 0
    }
    if reactive, next.available, next.musicActive {
      for (index, event) in [next.impact, next.accent, next.beat, next.flash].enumerated() {
        if event.active, event.serial > lastEvents[index] {
          pendingPulse = max(pendingPulse, event.strength)
          lastEvents[index] = event.serial
        }
      }
    } else { pendingPulse = 0 }
    return changed
  }

  func setPlaying(_ next: Bool, hostTime: Double) {
    guard next != playing else { return }
    playing = next
    lastHostTime = hostTime
    if !next { pendingPulse = 0 }
  }

  func uniforms(size: CGSize, hostTime: Double, reducedMotion: Bool) -> [Float] {
    guard hostTime.isFinite, size.width > 0, size.height > 0 else { return [] }
    if playing, let previous = lastHostTime {
      elapsed += max(0, min(hostTime - previous, 0.25)) * (reducedMotion ? 0.1 : 1)
    }
    lastHostTime = hostTime
    let input = reactive && playing && frame?.available == true && frame?.musicActive == true ? frame : nil
    let pulse = input == nil || reducedMotion ? 0 : pendingPulse
    pendingPulse = 0
    return [Float(size.width), Float(size.height), Float(elapsed), Float(bitPattern: seed),
      input?.dynamics[1] ?? 0, input?.channels[0] ?? 0, input?.channels[1] ?? 0, input?.channels[2] ?? 0,
      input?.channels[3] ?? 0, pulse, input?.rhythm[1] ?? 0, input?.rhythm[0] ?? 0] + controls + program.colors
  }

  func inheritAnimation(from previous: SceneCatalogShaderState) -> Bool {
    guard let previous = previous as? SceneCreatorShaderState, previous.program.id == program.id else { return false }
    playing = previous.playing; elapsed = previous.elapsed; lastHostTime = previous.lastHostTime
    frame = previous.frame; eventSession = previous.eventSession; lastEvents = previous.lastEvents
    pendingPulse = reactive ? previous.pendingPulse : 0
    return true
  }
}

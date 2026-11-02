#!/usr/bin/env python3
"""Run the production native cadence policy, plus its three renderer bindings."""
from pathlib import Path
import subprocess
import tempfile

runtime = Path(__file__).resolve().parents[1] / 'Classes' / 'Runtime'
program = (runtime / 'SceneCatalogNativeProgram.swift').read_text()
start = program.index('struct SceneNativeThermalCadencePolicy {')
end = program.index('/// The existing scene owner supplies time', start)
production = program[start:end]

# The pure rule must govern the actual program and composition clocks too.
getter = program.split('  var preferredFramesPerSecond: Int {', 1)[1].split('\n  }', 1)[0]
assert 'SceneNativeThermalCadence.maximumFramesPerSecond()' in getter
assert 'isNative' not in getter, 'Shaders and song programs must also be constrained'
assert 'min(descriptor.framesPerSecond,' in getter, 'Never increase authored cadence'
for filename, anchor in [
    ('MusicVibeRenderEngine.swift', 'private func reconcileForegroundTimer()'),
    ('PictureInPictureHandler.swift', 'func preferredFramesPerSecond(frame: SceneSurfaceReactiveFrame)'),
]:
    method = (runtime / filename).read_text().split(anchor, 1)[1].split('\n    }', 1)[0]
    assert 'SceneNativeThermalCadence.maximumFramesPerSecond()' in method, filename

tests = r'''
func sample(_ p: inout SceneNativeThermalCadencePolicy, _ state: Int,
            _ time: Double, lowPower: Bool = false) -> Int {
  p.maximumFramesPerSecond(thermalState: state, lowPowerMode: lowPower, uptime: time)
}
func expect(_ actual: Int, _ expected: Int, _ name: String) {
  precondition(actual == expected, "\(name): \(actual) != \(expected)")
}
var normal = SceneNativeThermalCadencePolicy()
expect(sample(&normal, 0, 0), 60, "nominal")
expect(sample(&normal, 0, 1, lowPower: true), 30, "battery saver")
expect(sample(&normal, 0, 2), 60, "battery saver release")
var warm = SceneNativeThermalCadencePolicy()
for t in [0.0, 10, 20, 29] { expect(sample(&warm, 1, t), 60, "transient fair") }
expect(sample(&warm, 1, 30), 30, "sustained fair")
for t in [31.0, 45, 60, 75, 90] { expect(sample(&warm, 0, t), 30, "recovery hysteresis") }
expect(sample(&warm, 0, 91), 60, "confirmed cool recovery")
var hot = SceneNativeThermalCadencePolicy()
expect(sample(&hot, 2, 0), 24, "serious immediate")
expect(sample(&hot, 3, 1, lowPower: true), 15, "critical precedes low power")
expect(sample(&hot, 1, 2), 30, "fair cannot instantly restore full rate")
var gap = SceneNativeThermalCadencePolicy()
expect(sample(&gap, 1, 0), 60, "gap start")
expect(sample(&gap, 1, 40), 60, "unobserved time is not sustained warmth")
for t in [50.0, 60, 70] { _ = sample(&gap, 1, t) }
expect(sample(&gap, 1, 71), 30, "observed warm interval after gap")
expect(sample(&gap, 0, 200), 30, "unobserved time is not cool recovery")
var missing = SceneNativeThermalCadencePolicy()
for t in [0.0, 10, 20] { _ = sample(&missing, 1, t) }
expect(sample(&missing, -1, 25), 60, "unknown interrupts warm observation")
expect(sample(&missing, 1, 30), 60, "warm interval starts again")
expect(sample(&missing, 2, 31), 24, "serious still immediate")
expect(sample(&missing, -1, 32), 30, "unknown cannot prove cool recovery")
var frequent = SceneNativeThermalCadencePolicy()
for _ in 0..<10000 { expect(sample(&frequent, 1, 0), 60, "layers do not accelerate the clock") }
for t in [10.0, 20, 30] { _ = sample(&frequent, 1, t) }
expect(sample(&frequent, 1, 31), 30, "one window across layers")
print("Native thermal cadence: warm window, recovery, gaps, unknown, low power, severity and shared observations passed.")
'''
with tempfile.TemporaryDirectory(prefix='scene-thermal-') as tmp:
    folder = Path(tmp)
    source = folder / 'main.swift'
    source.write_text('import Foundation\n' + production + tests)
    binary = folder / 'thermal-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path',
                    str(folder / 'modules'), str(source), '-o', str(binary)],
                   check=True, timeout=90)
    subprocess.run([str(binary)], check=True, timeout=15)
print('Native program, composition and foreground timer bindings passed.')

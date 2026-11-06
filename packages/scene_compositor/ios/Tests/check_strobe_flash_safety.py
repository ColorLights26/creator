#!/usr/bin/env python3
"""Timer-driven strobes keep the photosensitivity ceiling (05-nov-2026).

Colorful Illumination blinked 50 ms colour / 50 ms black (10 flashes per
second) and Dance Dance read its stored Velocity as a different rhythm on
iPhone than on Android. The music-flash ceiling (Dart VisualSafetyPolicy)
did not cover flashes that follow a clock.

1. Extracts the production strobe types (StrobeProgram, StrobeLayer,
   StrobeOptions, StrobeFrame, StrobeState, strobeOptions) and the
   SceneRenderV2FlashSafety ceiling, compiles them on macOS with
   strobe_flash_safety_tests.swift and plays them frame by frame, counting
   the changes in every one-second window.
2. Feeds the t_bw mode values the Dart schema stores (legacy_native_controls)
   so a mode means one rhythm on both platforms.
3. Checks that the scene graph cadence follows the capped phase.

Usage: check_strobe_flash_safety.py [SceneRenderV2ImageSurface.swift]
                                    [legacy_native_controls.dart]
"""
from pathlib import Path
import json
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'Classes/Runtime'
SURFACE = RUNTIME / 'SceneRenderV2ImageSurface.swift'
SIGNAL = RUNTIME / 'SceneRenderSignalFrameV2.swift'
TESTS = Path(__file__).resolve().parent / 'strobe_flash_safety_tests.swift'
SCHEMAS = ROOT.parents[3] / 'audiovisuals/lib/native/legacy_native_controls.dart'

NESTED = (
    r'enum StrobeProgram\b',
    r'struct StrobeLayer\b',
    r'struct StrobeOptions\b',
    r'struct StrobeFrame\b',
    r'final class StrobeState\b',
    r'static func strobeOptions\(',
)


def extract(source):
    parts = []
    for declaration in NESTED:
        found = re.search(
            r'^  private ' + declaration + r'.*?^  \}\n', source, re.M | re.S
        )
        if found is None:
            raise SystemExit(f'Strobe flash safety broken: missing {declaration}')
        parts.append(found.group().replace('  private ', '  ', 1))
    ceiling = re.search(
        r'^enum SceneRenderV2FlashSafety \{.*?^\}\n', source, re.M | re.S
    )
    return parts, ceiling.group() if ceiling else ''


def t_bw_velocities(schemas_path):
    text = schemas_path.read_text()
    payload = text.split('const _schemas = <String, Map<String, Object?>>', 1)[1]
    schemas = json.loads(re.sub(r';\s*\Z', '', payload))
    modes = schemas['t_bw']['modes']
    return {name: float(values['Velocity']) for name, values in modes.items()}


def cadence_follows_capped_phase(source):
    found = re.search(
        r'case \.strobe\(let layer, _\):\n\s*guard let interval = (\S+) else',
        source,
    )
    return found is not None and found.group(1) == 'layer.options.intervalMicros'


def main():
    surface = Path(sys.argv[1]) if len(sys.argv) > 1 else SURFACE
    schemas = Path(sys.argv[2]) if len(sys.argv) > 2 else SCHEMAS
    source = surface.read_text()
    parts, ceiling = extract(source)
    velocities = t_bw_velocities(schemas)
    failures = 0
    with tempfile.TemporaryDirectory(prefix='strobe-flash-safety-') as path:
        production = Path(path) / 'production.swift'
        production.write_text(
            'import Foundation\nimport CoreGraphics\nimport CoreImage\n'
            'struct Plan { let playing: Bool }\n'
            + ceiling
            + 'final class StrobeHarness {\n' + ''.join(parts) + '}\n'
        )
        literal = ', '.join(f'{json.dumps(k)}: {v}' for k, v in velocities.items())
        tests = Path(path) / 'main.swift'
        tests.write_text(
            f'let schemaVelocityByMode: [String: Double] = [{literal}]\n'
            + TESTS.read_text()
        )
        binary = Path(path) / 'tests'
        subprocess.run(
            ['xcrun', 'swiftc', '-suppress-warnings', str(production),
             str(SIGNAL), str(tests), '-o', str(binary)],
            check=True,
        )
        failures += subprocess.run([str(binary)]).returncode != 0
    if cadence_follows_capped_phase(source):
        print('PASS graph cadence follows the capped strobe phase')
    else:
        print('FAIL graph cadence still follows the uncapped program interval')
        failures += 1
    if failures:
        raise SystemExit('Strobe flash safety broken')
    print('PASS strobe flash safety')


if __name__ == '__main__':
    main()

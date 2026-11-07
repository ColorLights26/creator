#!/usr/bin/env python3
"""Reactive video light that follows the beats (06-nov-2026, «Seguir los golpes»).

1. Extracts the production `SceneRenderV2RGBGainConfig`,
   `SceneRenderV2RGBGainState` and `SceneRenderV2FlashSafety`, compiles them on
   macOS with SceneRenderSignalFrameV2.swift and rgb_gain_pulse_tests.swift,
   and plays beats through them: the light must follow each beat, keep the
   20 % ceiling, admit at most three pulses in any second, and never count as
   a change under the Creator flash rule (>=5 of 16 zones move >48 levels),
   measured on real `CIColorMatrix` output.
2. Checks that a video layer's light never asks for a presentation of its own:
   it rides on the next decoded video frame.
3. Does the same for the legacy compositor that iOS production uses
   (`SceneSurfaceRGBGainEffectRuntime` in PictureInPictureHandler.swift), and
   checks that both share one ceiling on a monotonic clock: a new audio session
   or a second reactive layer never lets more than three pulses into a second.
4. The beat in the bright zones only (`SceneRenderV2HighlightLight`, the
   technique the user approved on 06-11): the lamp and its glow beat, the dark
   room stays, Healing is softer, both compositors give the same light, and
   the Creator flash rule holds.

Usage: check_rgb_gain_pulse.py [SceneRenderV2ImageSurface.swift [PictureInPictureHandler.swift]]
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'Classes/Runtime'
SURFACE = Path(sys.argv[1]) if len(sys.argv) > 1 else RUNTIME / 'SceneRenderV2ImageSurface.swift'
LEGACY = Path(sys.argv[2]) if len(sys.argv) > 2 else RUNTIME / 'PictureInPictureHandler.swift'
SIGNAL = RUNTIME / 'SceneRenderSignalFrameV2.swift'
TESTS = [Path(__file__).resolve().parent / name
         for name in ('rgb_gain_pulse_tests.swift', 'rgb_gain_legacy_tests.swift',
                      'rgb_gain_highlight_tests.swift')]

TOP_LEVEL = (
    r'enum SceneRenderV2FlashSafety \{',
    r'final class SceneRenderV2LightPulseLimiter \{',
    r'struct SceneRenderV2LightPulse \{',
    r'struct SceneRenderV2HighlightLight: Equatable \{',
    r'struct SceneRenderV2RGBGainConfig: Equatable \{',
    r'final class SceneRenderV2RGBGainState \{',
)
# File-private in production; the harness compiles them next to the tests.
LEGACY_TOP_LEVEL = (
    r'private struct SceneSurfaceReactiveFrame \{',
    r'private final class SceneSurfaceRGBGainEffectRuntime \{',
)
# The legacy layer samples its colour light on each decoded video frame and
# never asks for a composition, a timer rate or a render of its own for it.
LEGACY_RIDES_VIDEO = (
    r'if rgbGainRidesSourceFrames, sourceAdvanced \{\n'
    r'\s+rgbGainEffect\?\.sample\(frame: frame, hostTime: hostTime\)\n',
    r'let rgbGainAnimating = !rgbGainRidesSourceFrames &&\n',
    r'let rgbEffect = rgbGainRidesSourceFrames \? nil : rgbGainEffect\n',
    r'audioAdvanced: audioAdvanced && audioChangesComposition\n',
    r'var rgbGainRidesSourceFrames: Bool \{\n'
    r'\s+rgbGainEffect != nil && sourceKind == "video"\n',
    r'\(!layer\.rgbGainRidesSourceFrames &&\n'
    r'\s+layer\.rgbGainEffect\?\.needsFrames\(for: frame\) == true\)',
    r'if !layer\.rgbGainRidesSourceFrames,\n'
    r'\s+layer\.rgbGainEffect\?\.needsFrames\(for: frame\) == true \{',
    r'reactiveFrame\.keepImpact\(from: session\.reactiveFrame\)\n',
)


def main():
    source = SURFACE.read_text()
    parts = []
    for declaration in TOP_LEVEL:
        found = re.search(r'^' + declaration + r'.*?^\}\n', source, re.M | re.S)
        if found is None:
            raise SystemExit(f'RGB gain pulse broken: missing {declaration}')
        parts.append(found.group())

    media_consume = re.search(
        r'func consume\(_ frame: SceneRenderSignalFrameV2\) -> Bool \{\n'
        r'      let naturalChanged = naturalReactiveLightState\?\.consume\(frame\) \?\? false\n'
        r'(?:      //.*\n)*'
        r'      _ = rgbGainState\?\.consume\(frame\)\n'
        r'      return naturalChanged\n',
        source,
    )
    if media_consume is None:
        raise SystemExit('FAIL a video layer light asks for its own presentation')
    print('PASS a video layer light rides on the next decoded frame')

    legacy = LEGACY.read_text()
    for declaration in LEGACY_TOP_LEVEL:
        found = re.search(r'^' + declaration + r'.*?^\}\n', legacy, re.M | re.S)
        if found is None:
            raise SystemExit(f'RGB gain pulse broken: missing legacy {declaration}')
        parts.append(found.group()[len('private '):])
    for pattern in LEGACY_RIDES_VIDEO:
        if re.search(pattern, legacy) is None:
            raise SystemExit(f'FAIL legacy video light asks for frames of its own: {pattern}')
    print('PASS legacy video layer light rides on the next decoded frame')

    with tempfile.TemporaryDirectory() as folder:
        harness = Path(folder) / 'harness.swift'
        harness.write_text('import CoreImage\nimport Foundation\n\n' + '\n'.join(parts))
        binary = Path(folder) / 'rgb_gain_pulse'
        subprocess.run(
            ['xcrun', 'swiftc', '-O', '-o', str(binary), str(SIGNAL), str(harness),
             *[str(test) for test in TESTS]],
            check=True,
        )
        result = subprocess.run([str(binary)], text=True, capture_output=True)
        print(result.stdout, end='')
        if result.returncode != 0:
            print(result.stderr, end='')
            raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()

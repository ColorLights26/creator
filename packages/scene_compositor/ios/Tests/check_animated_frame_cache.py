#!/usr/bin/env python3
"""Replay the catalog GIF overlays through the production LZ4 frame copy and
its per-layer cache on macOS, then check how the layer runtime wires them.

Every frame must come back byte-identical at any cadence, per layer and within
the budget. The declarations are extracted by regex from the canonical Swift,
exactly like check_image_orientation.py; nothing in production changes. The
wiring checks read the runtime's own decode, load and tear-down paths, so the
cache cannot pass while the layer bypasses it.

Usage: check_animated_frame_cache.py [GIF ...]
Without arguments it uses the GIF overlays of the sibling audiovisuals module.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

# The thumbnail options of decodeAnimatedFrame, also used by the Swift test.
FRAME_OPTIONS = (
    'kCGImageSourceCreateThumbnailFromImageAlways: true',
    'kCGImageSourceCreateThumbnailWithTransform: true',
    'kCGImageSourceThumbnailMaxPixelSize: 1440',
    'kCGImageSourceShouldCacheImmediately: false',
)


def method_body(source, anchor):
    """The method that starts at `anchor`, up to its closing brace."""
    start = source.index(anchor)
    end = source.index('\n    }\n', start)
    return source[start:end]


def require(condition, message):
    if not condition:
        raise RuntimeError(f'Layer runtime wiring broken: {message}')


def check_runtime_wiring(source, test_source):
    runtime = source[source.index('private final class PictureInPictureSceneLayerRuntime {'):]

    # 1. A kept copy replays before ImageIO decodes again, and only a fresh
    #    decode is offered to the cache.
    decode = method_body(runtime, '    private func decodeAnimatedFrame(at index: Int) -> CIImage? {')
    lookup = 'if let copy = compressedAnimatedFrames.image(at: index) {'
    thumbnail = 'CGImageSourceCreateThumbnailAtIndex('
    remember = 'compressedAnimatedFrames.remember(frame, at: index)'
    require(lookup in decode, 'decodeAnimatedFrame must replay a kept copy')
    require(thumbnail in decode and decode.index(lookup) < decode.index(thumbnail),
            'the kept copy is read before decoding again')
    require(remember in decode and decode.index(thumbnail) < decode.index(remember),
            'a fresh decode is offered to the cache')
    require(runtime.count('compressedAnimatedFrames.remember(') == 1,
            'only decodeAnimatedFrame keeps copies')
    for option in FRAME_OPTIONS:
        require(option in decode, f'decodeAnimatedFrame must keep {option}')
        require(option in test_source, f'the Swift test must decode with {option}')

    # 2. The layer's tear-down and every new source drop the old copies.
    teardown = method_body(runtime, '    func tearDown() {')
    require('retireVideo()' in teardown and 'animatedImageSource = nil' in teardown,
            'the first tearDown after the class is the layer runtime one')
    require('compressedAnimatedFrames.removeAll(keepingCapacity: false)' in teardown,
            'tearDown must drop the kept copies')
    load = method_body(runtime, '    private func loadAnimatedImage(path: String) -> Bool {')
    reset = 'compressedAnimatedFrames.removeAll(keepingCapacity: true)'
    require(reset in load, 'a new animated source must start with an empty cache')
    require(load.index(reset) < load.index('decodeAnimatedFrame(at: 0)'),
            'the cache is reset before the first frame of the new source')


def catalog_overlays(package):
    overlays = (package.parents[2] / 'audiovisuals' / 'assets' / 'audiovisuals'
                / 'transparents')
    gifs = sorted(overlays.glob('*.gif'))
    if len(gifs) < 2:
        raise RuntimeError(f'No catalog GIF overlays in {overlays}; pass GIF paths')
    return gifs


def main():
    package = Path(__file__).resolve().parents[2]
    source = (package / 'ios/Classes/Runtime/PictureInPictureHandler.swift').read_text()
    test = package / 'ios/Tests/animated_frame_cache_tests.swift'
    check_runtime_wiring(source, test.read_text())
    extracts = []
    for declaration in [r'let sceneSurfaceAnimatedImageCompressedCacheBytesLimit = .*?$',
                        r'struct SceneSurfaceCompressedAnimatedFrame \{.*?^}',
                        r'struct SceneSurfaceCompressedAnimatedFrameCache \{.*?^}']:
        found = re.search(r'^' + declaration, source, re.M | re.S)
        if not found:
            raise RuntimeError(f'Production declaration missing: {declaration}')
        extracts.append(found.group())
    gifs = [Path(path) for path in sys.argv[1:]] or catalog_overlays(package)
    with tempfile.TemporaryDirectory(prefix='animated-frame-cache-') as path:
        directory = Path(path)
        production = directory / 'AnimatedFrameCache.swift'
        production.write_text('import Compression\nimport CoreGraphics\nimport Foundation\n'
                              + '\n'.join(extracts))
        executable = directory / 'animated-frame-cache-tests'
        subprocess.run(['xcrun', 'swiftc', str(production), str(test),
                        '-o', str(executable)], check=True, timeout=180)
        subprocess.run([str(executable), *map(str, gifs)], check=True, timeout=600)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Exercise the production PiP restore barrier, return-presentation decisions,
stop-continuity rule, playback-intent gate, source-layer geometry and the
source host view on macOS, then check how the handler wires them.

The declarations are extracted by regex from the canonical Swift, exactly like
check_image_orientation.py; nothing in production changes. The wiring checks
read the handler's own call paths (the AVKit `setPlaying` delegate, the host
view attach, the layout-pass fit and the paths that enable an AVKit start) so
a pure helper cannot pass while the handler bypasses it.
"""
from pathlib import Path
import re
import subprocess
import tempfile


def method_body(source, anchor):
    """The handler method that starts at `anchor`, up to its closing brace."""
    start = source.index(anchor)
    end = source.index('\n    }\n', start)
    return source[start:end]


def require(condition, message):
    if not condition:
        raise RuntimeError(f'Handler wiring broken: {message}')


def check_handler_wiring(source):
    # 1. AVKit's setPlaying: the gate decision governs the only native
    #    mutation and the Dart event; the ignore branch changes nothing.
    delegate = method_body(source, '        setPlaying playing: Bool\n    ) {')
    require('PictureInPicturePlaybackIntentGate.decide(' in delegate,
            'setPlaying must ask PictureInPicturePlaybackIntentGate.decide')
    require('returnRequested: returnPresentation.continuityRequested' in delegate,
            'setPlaying must feed the pending return to the gate')
    require(delegate.count('setPlaybackActive(') == 1,
            'setPlaying must mutate playback through exactly one setPlaybackActive call')
    require('setPlaybackActive(playing, emitPlaybackIntent: true)' in delegate,
            'an applied control reports the intent to Dart')
    ignore_start = delegate.index('case .ignore:')
    apply_start = delegate.index('case .apply:')
    require(ignore_start < apply_start, 'ignore branch precedes apply branch')
    ignore_branch = delegate[ignore_start:apply_start]
    for forbidden in ('setPlaybackActive(', 'emit(', 'playbackActive =',
                      'stopRenderTimer', 'pauseDynamicSources', 'startRenderTimer',
                      'playDynamicSources'):
        require(forbidden not in ignore_branch,
                f'the ignore branch must not call {forbidden}')
    require(delegate.index('setPlaybackActive(') > apply_start,
            'the single setPlaybackActive call lives in the apply branch')

    # 2. The host view is the subclass whose layout pass fits the layer.
    attach = method_body(source, '    private func attachSampleLayer() -> Bool {')
    require('PictureInPictureSourceHostView(frame: window.bounds)' in attach,
            'attach must create PictureInPictureSourceHostView')
    require('.onLayout = { [weak self] in self?.fitSourceLayer() }' in attach,
            'attach must wire the layout pass to fitSourceLayer')
    require('UIView(frame:' not in attach, 'attach must not create a plain UIView host')

    # 3. The fit uses the current host bounds and touches only the frame.
    fit = method_body(source, '    private func fitSourceLayer() {')
    require('pictureInPictureSourceLayerUpdate(' in fit and 'host: hostView.bounds' in fit
            and 'current: sampleLayer.frame' in fit,
            'fitSourceLayer must plan from the current host bounds and layer frame')
    for forbidden in ('tearDown', 'release', 'detachSampleLayer', 'flushAndRemoveImage',
                      'pauseDynamicSources', 'stopRenderTimer', 'reportedSourceExtentSnapshot',
                      'renderQueue.sync'):
        require(forbidden not in fit, f'fitSourceLayer must not call {forbidden}')
    require('step: "layout"' in fit, 'a changed fit logs the bounded layout receipt')

    # 4. Every path that enables an AVKit start syncs the layer first.
    for anchor in ('    private func start(result: @escaping FlutterResult) {',
                   '    private func prewarmAutomaticPictureInPictureIfNeeded() {',
                   '    func pictureInPictureControllerWillStartPictureInPicture('):
        require('layoutSourceLayer()' in method_body(source, anchor),
                f'{anchor.strip()} must call layoutSourceLayer()')
    sync = method_body(source, '    private func layoutSourceLayer() {')
    require('fitSourceLayer()' in sync, 'layoutSourceLayer ends in fitSourceLayer')

    # 5. The window shows Play/Pause only: a scene is live content with no
    #    seekable range, never "no content" (which would drop Play/Pause too).
    time_range = method_body(
        source, '    func pictureInPictureControllerTimeRangeForPlayback(')
    require('CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)'
            in time_range,
            'the playback time range must be live with no seekable window')
    require('.invalid' not in time_range.split('CMTimeRange(start:')[1],
            'the playback time range must never be invalid')
    require('controller.requiresLinearPlayback = true' in source,
            'the controller keeps linear playback')


def main():
    package = Path(__file__).resolve().parents[2]
    source = (package / 'ios/Classes/Runtime/PictureInPictureHandler.swift').read_text()
    extracts = []
    check_handler_wiring(source)
    for declaration in [r'func pictureInPictureKeepsPresentationThroughStop\(',
                        r'final class PictureInPictureRestoreBarrier \{',
                        r'final class PictureInPictureReturnPresentation \{',
                        r'struct PictureInPicturePlaybackIntentGate \{',
                        r'func pictureInPictureSourceLayerFrame\(',
                        r'func pictureInPictureSourceLayerUpdate\(',
                        r'final class PictureInPictureSourceHostView: UIView \{',
                        r'struct PictureInPictureGeometryReceipt: Equatable, CustomStringConvertible \{']:
        found = re.search(r'^' + declaration + r'.*?^}', source, re.M | re.S)
        if not found:
            raise RuntimeError(f'Production declaration missing: {declaration}')
        extracts.append(found.group())
    with tempfile.TemporaryDirectory(prefix='pip-restore-barrier-') as path:
        directory = Path(path)
        production = directory / 'RestoreBarrier.swift'
        production.write_text('import Foundation\nimport CoreGraphics\n' + '\n'.join(extracts))
        executable = directory / 'pip-restore-barrier-tests'
        subprocess.run(['xcrun', 'swiftc', str(production),
                        str(package / 'ios/Tests/pip_restore_barrier_tests.swift'),
                        '-o', str(executable)], check=True, timeout=90)
        subprocess.run([str(executable)], check=True, timeout=30)


if __name__ == '__main__':
    main()

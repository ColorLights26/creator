#!/usr/bin/env python3
"""An inspection that runs out of time is no verdict (05-nov-2026).

On a busy device the native preflight used to hit its own 2 s deadline,
answer «asset_unavailable» (as if a file were missing) and cache that answer,
so every retry got the same «no» and the scene stayed black. The attach
inspection likewise called a timeout «scene_document_invalid».

1. Extracts the production SceneSurfaceInspectionContext and
   SceneSurfaceInspectionVerdict, compiles them on macOS with
   preflight_timeout_tests.swift and runs them with a forced delay.
2. Checks that the handler's preflight, cache and attach inspection use them.

Usage: check_preflight_timeout.py [PictureInPictureHandler.swift]
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HANDLER = ROOT / 'Classes/Runtime/PictureInPictureHandler.swift'
TESTS = Path(__file__).resolve().parent / 'preflight_timeout_tests.swift'
DART_ISSUES = (
    ROOT.parents[3] / 'sharedkernel/lib/scene_render/scene_render_surface_interface.dart'
)


def method_body(source, anchor):
    start = source.index(anchor)
    end = source.index('\n    }\n', start)
    return source[start:end]


def require(condition, message):
    if not condition:
        raise SystemExit(f'Preflight timeout broken: {message}')


def run_forced_delay_tests(source):
    extracts = []
    for declaration in (
        r'final class SceneSurfaceInspectionContext \{',
        r'enum SceneSurfaceInspectionVerdict \{',
    ):
        found = re.search(r'^' + declaration + r'.*?^}', source, re.M | re.S)
        require(found is not None, f'missing {declaration[:-3]}')
        extracts.append(found.group())
    with tempfile.TemporaryDirectory(prefix='preflight-timeout-') as path:
        production = Path(path) / 'production.swift'
        production.write_text(
            'import Foundation\nimport QuartzCore\nimport AVFoundation\n'
            + '\n'.join(extracts)
        )
        # Top-level test statements are only allowed in main.swift.
        tests = Path(path) / 'main.swift'
        tests.write_text(TESTS.read_text())
        binary = Path(path) / 'tests'
        subprocess.run(
            ['xcrun', 'swiftc', '-suppress-warnings', str(production),
             str(tests), '-o', str(binary)],
            check=True,
        )
        subprocess.run([str(binary)], check=True)


def check_handler_wiring(source):
    constant = re.search(
        r'static let preflightTimedOutIssue = "([a-z_]+)"', source
    )
    require(constant is not None, 'missing preflightTimedOutIssue')
    require(
        f"timedOut('{constant.group(1)}')" in DART_ISSUES.read_text(),
        'native timed-out code must match the Dart timedOut wire value',
    )

    evaluate = method_body(source, '    func evaluatePreflight(')
    require(
        'SceneSurfaceInspectionContext(timeout:' in evaluate
        and 'inspectionContext: inspectionContext' in evaluate,
        'evaluatePreflight must own the inspection deadline it reports on',
    )
    require(
        'SceneSurfaceInspectionVerdict.preflightIssues(' in evaluate,
        'a construction that ran out of time must answer timed_out',
    )

    reply = source[
        source.index('Self.holdForQAPreflightDelay()\n                evaluation'):
    ]
    reply = reply[: reply.index('let inspectedAt')]
    require(
        'SceneSurfaceInspectionVerdict.mayCache(' in reply
        and 'self.cachedPreflightSignature = cacheable ? signature : nil' in reply
        and '!cacheable' in reply,
        'only an accepted scene may be cached',
    )

    operation = method_body(source, '    func start(on worker: DispatchQueue,')
    require(
        'SceneSurfaceInspectionVerdict.operationError(context: context)' in operation
        and '"scene_document_invalid"' not in operation,
        'an attach inspection that ran out of time must report a timeout',
    )

    # The document build after the inspection has its own clock too.
    builds = source.split('SceneSurfaceDocumentRuntime(')
    runtime_builds = [
        build for build in builds[1:] if 'inspectedVideos: videos' in build[:600]
    ]
    require(len(runtime_builds) == 2, 'expected the attach and update builds')
    for build in runtime_builds:
        require(
            'inspectionContext: constructionContext' in build[:600],
            'a document build must use a context it can read after a timeout',
        )
    require(
        'SceneSurfaceInspectionVerdict.operationError(\n'
        '                        context: constructionContext' in source
        and 'logAttachReceipt("failed", "scene_document_invalid")' not in source,
        'an attach build that ran out of time must report a timeout',
    )
    require(
        'SceneSurfaceInspectionVerdict.updateRejection(context: constructionContext)'
        in source
        and 'rejectAndRestore("scene_update_resources_unavailable")' not in source,
        'an update build that ran out of time must keep the scene and ask again',
    )


def main():
    handler = Path(sys.argv[1]) if len(sys.argv) > 1 else HANDLER
    source = handler.read_text()
    run_forced_delay_tests(source)
    check_handler_wiring(source)
    print('preflight timeout wiring: ok')


if __name__ == '__main__':
    main()

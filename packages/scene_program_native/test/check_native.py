#!/usr/bin/env python3
"""Run actual authored programs outside the app, with deadlines and sanitizers."""
import argparse
import os
import re
from pathlib import Path
import signal
import subprocess
import tempfile

# Timeout seconds per program under sanitizers: its replay, and the pass gate
# that plays it 14 s at its fps on the iPhone and the iPad surfaces (~0.5 s).
REPLAY_SECONDS = 2
PASS_GATE_SECONDS = 3

def run(args, timeout=90):
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise RuntimeError('Native validation timed out: ' + args[0])
    if output:
        print(output, end='')
    if process.returncode:
        raise RuntimeError('Native validation failed: ' + args[0])

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--generated', required=True)
    root = Path(__file__).resolve().parent.parent
    parser.add_argument('--signals', default=str(root.parent / 'visual_contract/test/fixtures/synthetic/signals.bin'),
                        help='Synthetic music for the modifier sweep (520-byte frames).')
    parser.add_argument('--strict-modifiers', action='store_true',
                        help='A modifier that never changes the drawing fails instead of warning.')
    parser.add_argument('--pass-report', choices=['harness'],
                        help='Only print each visual\'s max passes and bytes on the iPhone and iPad, '
                             'with the energy harness schedule (240 frames, the last 60 silent).')
    options = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='creator-sanitizers-') as tmp:
        template = (root.parent.parent/'templates/visual_template.dart').read_text()
        match = re.search(r'const nativeSource = r(?:\x27{3}|\x22{3})([\s\S]*?)(?:\x27{3}|\x22{3});', template)
        if not match: raise RuntimeError('Copyable native template not found')
        # Same shape as the reader native_compiler.dart writes before each visual.
        kinds = {'slider': 'float', 'steps': 'int', 'choice': 'int', 'toggle': 'bool'}
        declared = re.search(r'^const modifiers = \[([\s\S]*?)^\];', template, re.M)
        fields = ''.join(' %s %s;' % (kinds[kind], name) for kind, name in
                         re.findall(r"CreatorModifier\.(slider|steps|toggle|choice)\(\s*'([a-z][a-z0-9_]*)'",
                                    declared[1] if declared else ''))
        reader = 'struct Modifiers {%s };\ninline Modifiers modifiers(const Frame& f) { (void)f; return {}; }\n' % fields
        # And the transitions reader: decimals, a 0..1 fade or choice weights.
        glides = ''.join(' %s %s;' % ('CreatorChoiceGlide' if kind == 'choice' else 'float', name) for kind, name in
                         re.findall(r"CreatorModifier\.(slider|steps|toggle|choice)\(\s*'([a-z][a-z0-9_]*)'",
                                    declared[1] if declared else ''))
        reader += ('struct CreatorChoiceGlide { int from = 0, to = 0; float t = 1; float weight(int) const { return 0; } };\n'
                   'struct CreatorGlide {%s };\ninline CreatorGlide glide(const Frame& f) { (void)f; return {}; }\n' % glides)
        template_check = Path(tmp)/'template.cpp'
        template_check.write_text('#include "creator_scene.hpp"\nusing namespace creator;\n'+reader+match[1]+ '\nstatic_assert(std::is_base_of<Scene,Visual>::value);\n')
        run(['clang++','-std=c++17','-fsyntax-only','-I'+str(root/'src'),str(template_check)])
        common = ['clang++' , '-std=c++17', '-g', '-O1', '-fsanitize=address,undefined',
                  '-fno-omit-frame-pointer', '-I' + str(root / 'src'), str(root / 'src/creator_scene.cpp')]
        unit = str(Path(tmp) / 'runtime-test')
        run(common + [str(root / 'test/runtime_test.cpp'), '-o', unit])
        run([unit], timeout=10)
        authored = str(Path(tmp) / 'authored-test')
        # The caps only catch a hung tool: they grow with the catalog (every
        # program is compiled, replayed under sanitizers and played 14 s on
        # two surfaces to count its passes; each one with modifiers or
        # variations is also swept).
        generated = Path(options.generated).resolve()
        programs = (generated / 'creator_programs.inc').read_text().count('namespace authored_')
        cases_file = generated / 'creator_probe_cases.inc'
        # Swept visuals only: the pass gate's list (creatorPassCases) comes after them.
        cases = cases_file.read_text().split('creatorPassCases')[0].count('{"creator_') if cases_file.exists() else 0
        run(common + ['-I' + str(generated), str(root / 'src/creator_registry.cpp'),
                      str(root / 'test/authored_probe.cpp'), '-o', authored], timeout=90 + 2 * programs)
        # Recorre todo el catálogo con ASan/UBSan: el tiempo crece con cada
        # visual. El tope sólo debe atrapar un programa colgado.
        sweep = [options.signals] + (['--strict-modifiers'] if options.strict_modifiers else [])
        if options.pass_report:
            sweep += ['--pass-report', options.pass_report]
        run([authored, *sweep], timeout=120 + (REPLAY_SECONDS + PASS_GATE_SECONDS) * programs + 30 * cases)

if __name__ == '__main__':
    main()

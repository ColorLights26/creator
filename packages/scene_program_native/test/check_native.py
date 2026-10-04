#!/usr/bin/env python3
"""Run actual authored programs outside the app, with deadlines and sanitizers."""
import argparse
import os
import re
from pathlib import Path
import signal
import subprocess
import tempfile

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
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
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
        template_check = Path(tmp)/'template.cpp'
        template_check.write_text('#include "creator_scene.hpp"\nusing namespace creator;\n'+reader+match[1]+ '\nstatic_assert(std::is_base_of<Scene,Visual>::value);\n')
        run(['clang++','-std=c++17','-fsyntax-only','-I'+str(root/'src'),str(template_check)])
        common = ['clang++' , '-std=c++17', '-g', '-O1', '-fsanitize=address,undefined',
                  '-fno-omit-frame-pointer', '-I' + str(root / 'src'), str(root / 'src/creator_scene.cpp')]
        unit = str(Path(tmp) / 'runtime-test')
        run(common + [str(root / 'test/runtime_test.cpp'), '-o', unit])
        run([unit], timeout=10)
        authored = str(Path(tmp) / 'authored-test')
        run(common + ['-I' + str(Path(options.generated).resolve()), str(root / 'src/creator_registry.cpp'),
                      str(root / 'test/authored_probe.cpp'), '-o', authored])
        # Recorre todo el catálogo con ASan/UBSan: el tiempo crece con cada
        # visual. El tope sólo debe atrapar un programa colgado.
        run([authored], timeout=120)

if __name__ == '__main__':
    main()

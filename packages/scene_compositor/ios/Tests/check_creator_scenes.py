#!/usr/bin/env python3
"""Build and inspect real native scenes on Metal, without application services."""
import argparse
import importlib.util
from pathlib import Path
import re
import tempfile

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--generated', required=True)
    parser.add_argument('--catalog', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    package = Path(__file__).resolve().parents[2]
    native = package.parent / 'scene_program_native'
    spec = importlib.util.spec_from_file_location('native_check', native/'test/check_native.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    run = module.run
    runtime = package/'ios/Classes/Runtime'
    with tempfile.TemporaryDirectory(prefix='creator-metal-') as directory:
        tmp = Path(directory)
        run(['clang++', '-std=c++17', '-O2', '-dynamiclib', str(native/'src/creator_scene.cpp'),
             str(native/'src/creator_registry.cpp'), '-I'+str(Path(args.generated).resolve()),
             '-o', str(tmp/'libscene_program_native.dylib')])
        (tmp/'module.modulemap').write_text('module scene_program_native {\n header "'+str(native/'src/creator_abi.h')+'"\n export *\n}\n')
        source = (runtime/'SceneRenderV2ImageSurface.swift').read_text()
        allocator = re.search(r'@available\(iOS 15\.0, \*\)\n(?:private )?final class SceneSurfaceNativeOutputAllocator \{.*?^\}',source,re.S|re.M)
        if not allocator:
            raise RuntimeError('Production allocator not found')
        (tmp/'Allocator.swift').write_text('import Foundation\nimport Metal\n'+allocator.group())
        executable = str(tmp/'scene-tests')
        run(['xcrun','swiftc','-O','-I',str(tmp),'-L',str(tmp),'-lscene_program_native',
             '-Xlinker','-rpath','-Xlinker',str(tmp),'-o',executable,str(tmp/'Allocator.swift'),
             *map(str,sorted(runtime.glob('SceneCatalog*.swift'))),str(runtime/'SceneRenderSignalFrameV2.swift'),
             str(package/'ios/Tests/creator_scene_tests.swift')],timeout=120)
        run([executable,str(Path(args.catalog).resolve()),str(Path(args.output).resolve())],timeout=120)

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Exercise the exact production image loader and source identity on macOS."""
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    package = Path(__file__).resolve().parents[2]
    source = (package / 'ios/Classes/Runtime/PictureInPictureHandler.swift').read_text()
    extracts = []
    for declaration in [r'func sceneSurfaceLoadImage\(', r'enum SceneSurfaceLayerSourceIdentity \{']:
        found = re.search(r'^' + declaration + r'.*?^}', source, re.M | re.S)
        if not found:
            raise RuntimeError(f'Production declaration missing: {declaration}')
        extracts.append(found.group())
    with tempfile.TemporaryDirectory(prefix='scene-image-orientation-') as path:
        directory = Path(path)
        production = directory / 'ImageLoader.swift'
        production.write_text('import Foundation\nimport CoreGraphics\nimport CoreImage\n' + '\n'.join(extracts))
        executable = directory / 'image-orientation-tests'
        subprocess.run(['xcrun', 'swiftc', str(production),
                        str(package / 'ios/Tests/image_orientation_tests.swift'),
                        '-o', str(executable)], check=True, timeout=45)
        subprocess.run([str(executable), str(directory)], check=True, timeout=30)


if __name__ == '__main__':
    main()

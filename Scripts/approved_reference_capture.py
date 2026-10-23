#!/usr/bin/env python3
"""Additional native 375x812pt verification; preserves existing capture defaults."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

from build_ios import BuildError
from ui_preview import capture

DEVICE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro'
SCREENS = ['assessment-goal', 'assessment-gender', 'assessment-age', 'assessment-height',
           'assessment-weight', 'assessment-target', 'assessment-activity', 'fitness-plan',
           'food-portion', 'approved-home', 'approved-calorie', 'approved-scan', 'approved-results']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--packages', type=Path, default=Path('BuildOutput/Packages'))
    parser.add_argument('--app', type=Path)
    parser.add_argument('--bundle-id', default='app.luqma.diary')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', args.bundle_id):
        parser.error('Invalid bundle identifier')
    output = args.output.resolve()
    capture(output, args.packages.resolve(), args.app.resolve() if args.app else None,
            args.bundle_id, 6.0, DEVICE, 'ar', SCREENS, True)
    report = json.loads((output/'ui-preview.json').read_text('utf-8'))
    if (report['status'] != 'captured' or report['simulator']['device_type'] != DEVICE
            or report['simulator']['device'] != 'iPhone 11 Pro'
            or report['screenshot_count'] != 13 or not report['runtime_fonts_verified']):
        raise BuildError('The exact reference capture did not produce the required native evidence')
    for image in report['screenshots']:
        data = (output/image['file']).read_bytes()
        if (data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (1125, 2436)
                or hashlib.sha256(data).hexdigest() != image['sha256']):
            raise BuildError('Native framebuffer does not match the 1125x2436 reference; no resizing allowed')
    audit = dict(status='captured', source=report['commit'], captures=13,
                 device=report['simulator'], native_pixels=[1125, 2436],
                 reference_pixels=[1125, 2436], runtime_fonts_verified=True,
                 original_images_modified=False, synthetic_ui_data=True,
                 functional_acceptance=False, pixel_match_claimed=False,
                 physical_fps_verified=False)
    (output/'exact-reference-audit.json').write_text(json.dumps(audit, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(audit))


if __name__ == '__main__':
    try:
        main()
    except (BuildError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)

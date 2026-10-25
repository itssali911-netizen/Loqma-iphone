"""Actual source-pixel checks, not a substitute for native UI comparison."""
import json
from pathlib import Path
import re
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Scripts'))
from ui_preview import decode_png

class SandowSourcePaletteTests(unittest.TestCase):
    def test_all_seventy_native_tokens_equal_supplied_reference_pixels(self):
        data=json.loads((ROOT/'Docs/SandowComponentSystem/extracted-tokens.json').read_text('utf8'))
        width,height,channels,pixels,_=decode_png((ROOT/'Docs/SandowComponentSystem/reference/palette.png').read_bytes(),'supplied-sandow-palette.png')
        self.assertEqual((width,height),(1440,3330))
        native=dict(re.findall(r'static let (\w+)=VisualRGB\(hex:0x([A-F0-9]{6})\)',(ROOT/'Luqma/Core/SandowDesignSystem.swift').read_text('utf8')))
        self.assertEqual(len(data['palette']),70)
        self.assertEqual(len({x['name'] for x in data['palette']}),70)
        for token in data['palette']:
            with self.subTest(token=token['name']):
                x,y=token['sample_in_palette_crop'];offset=(y*width+x)*channels
                rgb=bytes(pixels[offset:offset+3]).hex().upper()
                self.assertEqual('#'+rgb,token['hex'])
                self.assertEqual(native[token['name']],rgb)
        # Prevent an anti-aliased border/text sample being accepted as a fill.
        self.assertEqual(native['gray100'],'111214')
        self.assertEqual(native['orange50'],'F97316')

if __name__=='__main__':unittest.main()

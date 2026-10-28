"""Protect the four exact, user-supplied category photographs from swaps.

These checks validate real asset bytes and catalog metadata, not rendered UI.
Simulator screenshots and interaction tests remain necessary separately.
"""
import hashlib
import json
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Luqma/Resources/Assets.xcassets"
# Original attachment SHA-256. Re-encoding, substituting or swapping artwork
# must be an explicit design decision, rather than an unnoticed packaging edit.
ORIGINALS = {
    "DailyMealBreakfast": "fcf0a463ed2d437fc481832c5e82443e34b70f339703fe511198b71a880cd681",
    "DailyMealLunch": "191bd21e8a1509b150e83c12cf3189f774b5b78b4fe43776e673f8c7d403f708",
    "DailyMealDinner": "4de9b9d54cdeeb318df25b717b4f25ba9a0e76a1ee9cf922faa2b567fbca6b1a",
    "DailyMealSnack": "4a66f623dd4b4ed34b26660b6b48940187360cf4272022cdb9c06a28bed7be97",
}


class StrictMealArtworkTests(unittest.TestCase):
    def test_each_meal_catalog_contains_its_exact_original_attachment(self):
        for asset, expected in ORIGINALS.items():
            with self.subTest(asset=asset):
                folder = CATALOG / (asset + ".imageset")
                catalog = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
                images = [item for item in catalog["images"] if item.get("filename")]
                self.assertEqual(len(images), 1)
                image = images[0]
                self.assertEqual(image.get("idiom"), "universal")
                filename = image["filename"]
                self.assertEqual(Path(filename).name, filename)
                data = (folder / filename).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), expected)
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(data[12:16], b"IHDR")
                self.assertEqual(struct.unpack(">II", data[16:24]), (1024, 572))
                # Category photographs must retain their natural colors.
                self.assertNotEqual(catalog.get("properties", {}).get("template-rendering-intent"), "template")

    def test_all_four_meals_use_distinct_original_images(self):
        digests = []
        for asset in ORIGINALS:
            folder = CATALOG / (asset + ".imageset")
            catalog = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
            image = next(item for item in catalog["images"] if item.get("filename"))
            digests.append(hashlib.sha256((folder / image["filename"]).read_bytes()).hexdigest())
        self.assertEqual(len(set(digests)), 4, "A meal photograph was reused for another category")


if __name__ == "__main__":
    unittest.main()

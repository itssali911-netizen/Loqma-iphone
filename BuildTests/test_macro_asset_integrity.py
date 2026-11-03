"""Validate approved vector bytes and native catalog packaging, not rendered UI."""
import hashlib
import json
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Luqma/Resources/Assets.xcassets"
# Exact SVG bytes from recipe-card-edit-package.zip (2026-11-03).
# These are vectors derived from the supplied reference, not designer originals.
APPROVED = {
    "CalorieCardProtein": ("40838354c53bf33f33167972932155f0d4981ca4e53beaa84bfcb00d45cab368", "#EF798E"),
    "CalorieCardCarbs": ("77b5bd2b974acbf142cb8b89038e8d278ab087b6e234f762255211776a7dd4f3", "#E8B34C"),
    "CalorieCardFat": ("a4657d5615f724b36f54ec9c9a566e21faa924606886a135fa5f2af8d27598ac", "#8FBE63"),
    "RecipeCardCalories": ("61f9a6919df44b70f8053cd2e93aef6f2a5fd4764c265e0b089e05dcaf92d497", "#E1945C"),
}


class MacroAssetIntegrityTests(unittest.TestCase):
    def test_supplied_vectors_are_exact_and_preserve_native_vector_rendering(self):
        for asset, (digest, color) in APPROVED.items():
            with self.subTest(asset=asset):
                folder = CATALOG / (asset + ".imageset")
                config = json.loads((folder / "Contents.json").read_text("utf-8"))
                images = [image for image in config["images"] if image.get("filename")]
                self.assertEqual(len(images), 1)
                image = images[0]
                self.assertEqual(image["idiom"], "universal")
                self.assertEqual(Path(image["filename"]).name, image["filename"])
                data = (folder / image["filename"]).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
                vector = ET.fromstring(data)
                self.assertEqual(vector.tag, "{http://www.w3.org/2000/svg}svg")
                self.assertEqual((vector.attrib["width"], vector.attrib["height"]), ("20", "20"))
                self.assertEqual(len(vector.attrib["viewBox"].split()), 4)
                paths = list(vector.iter("{http://www.w3.org/2000/svg}path"))
                self.assertTrue(paths)
                self.assertTrue(all(path.attrib.get("d") for path in paths))
                self.assertIn(color, {path.attrib.get("fill") for path in paths})
                self.assertTrue(config["properties"]["preserves-vector-representation"])
                self.assertEqual(config["properties"]["template-rendering-intent"], "template")

    def test_legacy_macro_artwork_is_not_referenced_by_active_swift_views(self):
        legacy = re.compile(r'"(?:AddMeal(?:Protein|Carbs|Fat)|DNM(?:Vertical(?:Protein|Carbs|Fat)Icon|CarbsToastIcon|ProteinBlueIcon|FatBoneIcon))"')
        for source in (ROOT / "Luqma/Views").glob("*.swift"):
            with self.subTest(source=source.name):
                self.assertIsNone(legacy.search(source.read_text("utf-8")), "A live view still uses a legacy macro glyph")


if __name__ == "__main__":
    unittest.main()
